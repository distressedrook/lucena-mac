import Foundation

/// Client-side mirror of the backend walk (`grounding_tools/drill.py` `DrillState`) — the adjudication
/// layer over the already-downloaded solution tree. In the fully-local puzzle flow it is the SOLE
/// adjudicator: it decides correct/wrong the instant a move is played, plays the opponent's reply, and
/// (for a multi-defence puzzle) holds each remaining sibling defence for the "Continue" button — no
/// `/move` round-trip. It must mirror `DrillState` EXACTLY (same match rule, same advance/backtrack),
/// or the badge and the board disagree; keep the two in lockstep.
final class DrillWalker {
    struct Verdict { let correct: Bool; let finished: Bool }
    /// A sibling defence held for the "Continue" button (mirrors DrillState.stack entries): the node the
    /// student solves next, the defence move that reaches it, and the line length to rewind to.
    private struct Pending { let then: PuzzleNode; let san: String; let uci: String; let branchLen: Int }
    /// What `continueBranch()` hands back so the client can rewind its line and play the sibling defence.
    struct Continuation { let branchLen: Int; let defenseSan: String; let defenseUci: String; let afterFen: String }

    private var current: PuzzleNode
    private var stack: [Pending] = []          // sibling defences still to solve, held for Continue
    private var lineLen: Int                   // mirrors the client's localLine length (for branch rewind)
    private(set) var finished = false
    // The opponent's auto-played reply to the LAST adjudicated move (nil if that move ended the line) —
    // so the client can play it on the board locally. Reset each adjudicate.
    private(set) var lastReply: Defense?
    // A line was just solved but a sibling defence remains: the client shows "Continue", which calls
    // `continueBranch()` to do the deferred backtrack. Mirrors DrillState.awaiting_continue.
    private(set) var awaitingContinue = false

    init(_ doc: PuzzleDoc) { current = doc.root; lineLen = 1 }   // seed ply = the root position

    /// Adjudicate a played move at the current position, advancing the walk on a correct move (mirrors
    /// `DrillState.play`). A wrong move leaves the walk untouched — the player retries the same node.
    func adjudicate(uci: String, san: String?) -> Verdict {
        lastReply = nil; awaitingContinue = false
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
        lineLen += 1                                  // the student's ply (the client appends it too)
        return Verdict(correct: true, finished: advance(chosenThen))
    }

    /// The opponent-reply / next-line bookkeeping (`DrillState._advance`). The first live defence is
    /// auto-played (surfaced via `lastReply`); the rest are held as siblings for Continue. Returns
    /// whether the drill is now finished.
    private func advance(_ node: PuzzleNode?) -> Bool {
        guard let node, node.kind == "reply" else { return nextOrFinish() }
        // Only defences that lead to ANOTHER move to find are drilled; a defence straight to `done` is a
        // one-move win. Siblings branch from HERE (after the student ply): stash the line length so
        // Continue can rewind to it. Pushed reversed so they pop in order — matches DrillState.
        let live = (node.defenses ?? []).filter { $0.then.isStudent }
        let branchLen = lineLen
        for d in live.dropFirst().reversed() {
            stack.append(Pending(then: d.then, san: d.san, uci: d.uci, branchLen: branchLen))
        }
        if let first = live.first {
            current = first.then
            lastReply = first                        // expose the opponent's reply for local board play
            lineLen += 1                             // the opponent's auto-played reply ply
            return false
        }
        return nextOrFinish()
    }

    /// A line ended. HOLD if a sibling defence remains (Continue does the backtrack); else finish.
    /// Mirrors `DrillState._next_or_finish` — it does NOT pop the stack, only flags awaiting-continue.
    private func nextOrFinish() -> Bool {
        if !stack.isEmpty {
            awaitingContinue = true
            return false
        }
        finished = true
        return true
    }

    /// The deferred backtrack — run only when the player clicks Continue (mirrors
    /// `DrillState.continue_branch`). Pops the held sibling and tells the client where to rewind its line
    /// and which defence to play. nil when nothing is pending (already finished / no siblings).
    func continueBranch() -> Continuation? {
        awaitingContinue = false
        guard let p = stack.popLast() else { finished = true; return nil }
        current = p.then
        lineLen = p.branchLen + 1                     // rewound to branchLen, then the sibling defence ply
        guard let after = p.then.fen else { return nil }
        return Continuation(branchLen: p.branchLen, defenseSan: p.san, defenseUci: p.uci, afterFen: after)
    }

    /// SAN is canonical (compare first); fall back to a UCI prefix match. Mirrors `_same_move`.
    static func sameMove(_ inSan: String?, _ inUci: String?, _ expSan: String?, _ expUci: String?) -> Bool {
        if let inSan, let expSan, inSan == expSan { return true }
        if let inUci, let expUci, expUci.hasPrefix(inUci) { return true }
        return false
    }
}
