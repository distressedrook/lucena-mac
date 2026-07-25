import Foundation

/// THE GAME SCORE — the Analysis panel's move list as data, kept free of SwiftUI so it can be
/// tested on its own (Tests/GameScoreTests.swift). The rendering lives in MoveListView.

/// One move in the GAME SCORE — the panel's PGN-style list. Unlike the navigator strip, the score
/// keeps the mainline WHOLE and shows an open variation as an indented aside beneath the move it
/// replaces (owner 2026-07-26, with a screenshot: "2. ♞f3 ♞c6" still reads as the game, with
/// "2… ♞f6" below it). So a score entry cannot be a bare index into the shown line — the two lists
/// hold different things — and it carries what to DO when it is clicked instead.
struct ScoreMove: Identifiable {
    enum Target {
        case mainline(Int)                                  // a ply — leaves any open variation
        case variation(stack: [VarSegment], cursor: Int)    // the exact line + move to open
    }
    let id: String
    let move: LineMove
    /// 0 = the game itself; 1 = a sideline off it; 2 = a sideline off that, and so on.
    let depth: Int
    /// Moves of one continuous run. Rows never pair across blocks — two different sidelines at the
    /// same move number must not end up sharing a row.
    let blockId: String
    let isCurrent: Bool
    let target: Target

    var isVariation: Bool { depth > 0 }
}

/// A move-list row: the move number and its (up to two) moves. `isVariation` rows render indented
/// behind a rule, with their numbers inline.
struct MoveRow: Identifiable {
    let id: String
    let number: Int
    let white: ScoreMove?
    let black: ScoreMove?
    let depth: Int
    let blockId: String

    var isVariation: Bool { depth > 0 }
}


/// Presentation for the move list. The pure grouping lives here; the figurine/notation helpers the
/// views use extend this enum from MoveListView.swift.
enum MoveListStyle {
    /// Group the score into numbered rows. Number and color come from each move's OWN resulting fen
    /// (LineMove.number / .whiteMoved), which is what makes one code path serve a mainline ply and a
    /// variation move at any depth: a black-to-move start reads "1… ", and a sideline picks up at
    /// its real move number instead of being renumbered from 1.
    ///
    /// Moves pair only within one continuous run (`blockId`): a sideline never joins a mainline row,
    /// two sidelines at the same move number never share one, and the mainline picks back up after
    /// an aside ("3. … a6" when the sideline replaced a white move) — how a printed score reads.
    static func rows(_ score: [ScoreMove]) -> [MoveRow] {
        var out: [MoveRow] = []
        for e in score {
            let m = e.move
            guard m.san != nil else { continue }        // the root "…" block is not a move
            // The navigator's "?" placeholder (the drill's parked wrong tries) is an affordance,
            // not a played move: it has no uci and no resulting position of its own, so numbering
            // it from the solve fen would print a move that was never made. The strip renders it
            // unnumbered; the game score simply doesn't carry it.
            guard !(m.uci == nil && m.san == "?") else { continue }
            if m.whiteMoved {
                out.append(MoveRow(id: e.id, number: m.number, white: e, black: nil,
                                   depth: e.depth, blockId: e.blockId))
            } else if let last = out.last, last.number == m.number, last.black == nil,
                      last.blockId == e.blockId,            // one run only — never across sidelines
                      !m.isBranch {                         // a branch always opens its own row
                out[out.count - 1] = MoveRow(id: last.id, number: last.number, white: last.white,
                                             black: e, depth: last.depth, blockId: last.blockId)
            } else {
                out.append(MoveRow(id: e.id, number: m.number, white: nil, black: e,
                                   depth: e.depth, blockId: e.blockId))
            }
        }
        return out
    }

    /// Build the score: the mainline whole, every recorded sideline as an aside beneath the move it
    /// replaces, sublines nested under theirs, and the tip's own alternatives at the end (a "what
    /// if" played from the live position is a variation like any other and must not vanish).
    ///
    /// `shown`/`cursor`/`inVariation` describe where the BOARD is, so exactly one move reads as
    /// current: a sideline move matches by node identity, and a cursor parked on the shared mainline
    /// prefix of an open variation matches by ply — reading `inVariation` alone would highlight
    /// nothing there.
    static func score(mainline: [LineMove], variations: VariationForest,
                      shown: [LineMove], cursor: Int, inVariation: Bool,
                      currentPly: Int) -> [ScoreMove] {
        let at = inVariation && shown.indices.contains(cursor) ? shown[cursor] : nil
        let live = at?.node
        let livePly = inVariation ? at?.mainPly : currentPly
        var out: [ScoreMove] = []
        for (i, m) in mainline.enumerated() {
            out.append(ScoreMove(id: m.id, move: m, depth: 0, blockId: "main",
                                 isCurrent: i == livePly, target: .mainline(i)))
            // Alternatives to THIS move branch from the position before it, so they are listed
            // right after it — the printed convention, and where the eye expects the aside.
            if i > 0 {
                out += asides(variations, from: mainline[i - 1].fen, replacing: i - 1,
                              parents: [], depth: 1, live: live, seen: [])
            }
        }
        // Sidelines off the LIVE position: alternatives to a move that has not been played yet.
        if let tip = mainline.last {
            out += asides(variations, from: tip.fen, replacing: mainline.count - 1,
                          parents: [], depth: 1, live: live, seen: [])
        }
        return out
    }

    /// Every sideline branching off `fen`, and their own sublines, as score entries. `replacing` is
    /// the index — in the line these moves would join — of the move they branch AFTER; that is
    /// exactly `VarSegment.branchLineIndex`, so each entry can carry the segment stack that opens it.
    private static func asides(_ variations: VariationForest, from fen: String,
                               replacing branchIndex: Int, parents: [VarSegment],
                               depth: Int, live: VarNode?, seen: Set<String>) -> [ScoreMove] {
        // A REPETITION would otherwise recurse forever: the forest is keyed by normalized fen, so a
        // line that returns to a position it already branched from (Nf3-g1-f3, a threefold, any
        // transposition) would walk into its own aside again. Each path remembers the keys it has
        // already opened.
        let key = VariationForest.norm(fen)
        guard !seen.contains(key) else { return [] }
        let seen = seen.union([key])
        var out: [ScoreMove] = []
        for head in variations.at(fen) {
            let nodes = head.line
            let stack = parents + [VarSegment(branchLineIndex: branchIndex, nodes: nodes)]
            for (j, node) in nodes.enumerated() {
                let cursor = branchIndex + 1 + j
                out.append(ScoreMove(
                    id: node.id.uuidString,
                    move: LineMove(id: node.id.uuidString, san: node.san, uci: node.uci,
                                   fen: node.fen, isBranch: j == 0, node: node, mainPly: nil),
                    depth: depth, blockId: head.id.uuidString,
                    isCurrent: node === live,
                    target: .variation(stack: stack, cursor: cursor)))
                // Sublines off the PREVIOUS node replace this one, so they follow it.
                if j > 0 {
                    out += asides(variations, from: nodes[j - 1].fen, replacing: cursor - 1,
                                  parents: stack, depth: depth + 1, live: live, seen: seen)
                }
            }
            // ...and sublines off the tip are alternative continuations of this line.
            if let tip = nodes.last {
                out += asides(variations, from: tip.fen, replacing: branchIndex + nodes.count,
                              parents: stack, depth: depth + 1, live: live, seen: seen)
            }
        }
        return out
    }
}
