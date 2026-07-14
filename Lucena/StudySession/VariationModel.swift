import Foundation

/// A user-authored variation move — a "what if" played off the mainline (or off another variation).
/// Reference type so the tree can hold parent/continuation links. Positions are computed locally
/// (`ChessMove.apply`); the engine still grounds their eval, but a variation never touches the drill.
final class VarNode: Identifiable {
    let id = UUID()
    let uci: String
    let san: String
    let fen: String            // the position AFTER this move
    var next: VarNode?         // this line's own continuation (its "mainline")

    init(uci: String, san: String, fen: String) {
        self.uci = uci; self.san = san; self.fen = fen
    }

    /// This node and every node reachable via `next` — the variation's principal line.
    var line: [VarNode] {
        var out: [VarNode] = []; var n: VarNode? = self
        while let node = n { out.append(node); n = node.next }
        return out
    }
}

/// One move as shown in the navigator strip — a mainline ply or a variation node, unified so the
/// strip renders a single flowing line (mainline → variation) regardless of source. `isBranch` marks
/// the move where the current segment diverged from its parent (the strip draws a marker there).
struct LineMove: Identifiable {
    let id: String
    let san: String?
    let uci: String?
    let fen: String            // position AFTER this move
    let isBranch: Bool         // first move of a variation segment (divergence point)
    let node: VarNode?         // the variation node (nil for mainline moves) — for caret/sub-variation lookup
    let mainPly: Int?          // the mainline ply index (nil for variation moves) — for caret lookup

    /// PGN move number + side, derived from the resulting fen so it's correct on any line: the mover is
    /// the side NOT to move in `fen`; white's number is the fen's fullmove, black's is one less.
    var number: Int {
        let f = fen.split(separator: " ")
        let full = f.count > 5 ? Int(f[5]) ?? 1 : 1
        return whiteMoved ? full : full - 1
    }
    var whiteMoved: Bool { (fen.split(separator: " ").dropFirst().first ?? "w") == "b" }
}

/// A chosen variation segment: the nodes of one sideline, and where (an index into the line built
/// from all PRIOR segments) it branches off. The screen keeps a stack of these — Back pops one.
struct VarSegment { let branchLineIndex: Int; var nodes: [VarNode] }

/// The variation forest for one game: alternatives keyed by the position they branch FROM (a
/// normalized fen, so clocks don't fragment it). A mainline position's key holds the sidelines off
/// it; a `VarNode`'s own fen key holds sub-variations off that node — so nesting is uniform and
/// depth-independent. Owned by the screen; ephemeral for now (session persistence is a later phase).
struct VariationForest {
    /// normalizedFen -> the first move of each variation branching from that position.
    private(set) var branches: [String: [VarNode]] = [:]

    static func norm(_ fen: String) -> String { fen.split(separator: " ").prefix(4).joined(separator: " ") }

    /// Variations that branch off `fen` (empty if none). Order = creation order.
    func at(_ fen: String) -> [VarNode] { branches[Self.norm(fen)] ?? [] }

    /// Does any variation branch off `fen`?
    func has(_ fen: String) -> Bool { !(branches[Self.norm(fen)] ?? []).isEmpty }

    /// Record `node` as a new variation branching off `fromFen`. If a sibling already plays the same
    /// move, return that existing node instead (so replaying a move re-enters its line, not a dup).
    mutating func add(_ node: VarNode, from fromFen: String) -> VarNode {
        let key = Self.norm(fromFen)
        var siblings = branches[key] ?? []
        if let existing = siblings.first(where: { $0.uci == node.uci }) { return existing }
        siblings.append(node); branches[key] = siblings
        return node
    }

    /// True when `uci` from `fromFen` already exists as a variation first-move.
    func existing(_ uci: String, from fromFen: String) -> VarNode? {
        (branches[Self.norm(fromFen)] ?? []).first { $0.uci == uci }
    }

    mutating func removeAll() { branches.removeAll() }
}
