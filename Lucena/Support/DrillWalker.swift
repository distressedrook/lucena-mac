import Foundation

/// Client-side mirror of the backend walk (`grounding_tools/drill.py` `DrillState`) — the OPTIMISTIC
/// adjudication layer over the already-downloaded solution tree. It decides correct/wrong the instant
/// a move is played, so the ✓/✗ badge and Retry appear WITHOUT waiting on `/move`.
///
/// The backend stays the source of truth: it re-adjudicates the same move, persists progress,
/// narrates the verdict, and plays the opponent's reply; its stream reconciles anything this got
/// wrong (the "you played" bubble carries a clientId the server echo matches). This walk therefore
/// tracks only what the badge needs — the current node to solve, the sibling-defence stack, and
/// whether the drill finished — NOT the board/move-line (that is the server's job). It must mirror
/// `DrillState` EXACTLY (same match rule, same advance/backtrack), or the optimistic badge will
/// disagree with the server and flicker; keep the two in lockstep.
final class DrillWalker {
    struct Verdict { let correct: Bool; let finished: Bool }

    private var current: PuzzleNode
    private var stack: [PuzzleNode] = []      // sibling defences still to solve (their `then` nodes)
    private(set) var finished = false

    init(_ doc: PuzzleDoc) { current = doc.root }

    /// Adjudicate a played move at the current position, advancing the walk on a correct move (mirrors
    /// `DrillState.play`). A wrong move leaves the walk untouched — the player retries the same node.
    func adjudicate(uci: String, san: String?) -> Verdict {
        var chosenThen: PuzzleNode?
        var matched = false
        switch current.kind {
        case "solve":
            matched = Self.sameMove(san, uci, current.expectSan, current.expectUci)
            chosenThen = current.after
        case "mate":
            for o in current.options ?? [] where Self.sameMove(san, uci, o.san, o.uci) {
                matched = true; chosenThen = o.then; break
            }
        default:
            break
        }
        guard matched else { return Verdict(correct: false, finished: false) }
        return Verdict(correct: true, finished: advance(chosenThen))
    }

    /// The opponent-reply / next-line bookkeeping (`DrillState._advance` + `_next_or_finish`), reduced
    /// to keeping `current` pointed at the next node to solve. The opponent's actual reply move is the
    /// server's to play; here we only step past it. Returns whether the drill is now finished.
    private func advance(_ node: PuzzleNode?) -> Bool {
        guard let node, node.kind == "reply" else { return nextOrFinish() }
        // Only defences that lead to ANOTHER move to find are drilled; a defence straight to `done`
        // is a one-move win. The first live defence is auto-played now; the rest are siblings to solve
        // after this line (pushed reversed so they pop in order — matches DrillState).
        let live = (node.defenses ?? []).filter { $0.then.isStudent }
        for d in live.dropFirst().reversed() { stack.append(d.then) }
        if let first = live.first {
            current = first.then
            return false
        }
        return nextOrFinish()
    }

    private func nextOrFinish() -> Bool {
        if let sibling = stack.popLast() {
            current = sibling
            return false
        }
        finished = true
        return true
    }

    /// SAN is canonical (compare first); fall back to a UCI prefix match. Mirrors `_same_move`.
    static func sameMove(_ inSan: String?, _ inUci: String?, _ expSan: String?, _ expUci: String?) -> Bool {
        if let inSan, let expSan, inSan == expSan { return true }
        if let inUci, let expUci, expUci.hasPrefix(inUci) { return true }
        return false
    }
}
