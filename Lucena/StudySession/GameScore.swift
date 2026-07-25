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
        case line(Int)        // an index into the shown line (a variation move, or the prefix)
        case mainline(Int)    // a mainline ply — selecting it leaves an open variation
    }
    let id: String
    let move: LineMove
    let isVariation: Bool
    let isCurrent: Bool
    let target: Target
}

/// A move-list row: the move number and its (up to two) moves. `isVariation` rows render indented
/// behind a rule, with their numbers inline.
struct MoveRow: Identifiable {
    let id: String
    let number: Int
    let white: ScoreMove?
    let black: ScoreMove?
    let isVariation: Bool
}


/// Presentation for the move list. The pure grouping lives here; the figurine/notation helpers the
/// views use extend this enum from MoveListView.swift.
enum MoveListStyle {
    /// Group the score into numbered rows. Number and color come from each move's OWN resulting fen
    /// (LineMove.number / .whiteMoved), which is what makes one code path serve a mainline ply and a
    /// variation move at any depth: a black-to-move start reads "1… ", and a sideline picks up at
    /// its real move number instead of being renumbered from 1.
    ///
    /// A variation move never pairs into a mainline row and vice versa — the aside is its own block,
    /// and the mainline picks back up afterwards ("3. … a6" when the sideline replaced a white
    /// move), which is how a printed game score reads.
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
                                   isVariation: e.isVariation))
            } else if let last = out.last, last.number == m.number, last.black == nil,
                      last.isVariation == e.isVariation,    // never pair a sideline onto the game
                      !m.isBranch {                         // a branch always opens its own row
                out[out.count - 1] = MoveRow(id: last.id, number: last.number, white: last.white,
                                             black: e, isVariation: e.isVariation)
            } else {
                out.append(MoveRow(id: e.id, number: m.number, white: nil, black: e,
                                   isVariation: e.isVariation))
            }
        }
        return out
    }
}
