import Foundation

// The puzzle solution TREE (engine-built), decoded from the `/state` `tree` event with
// `.convertFromSnakeCase`. At each of your turns there is one required move; at each opponent
// turn a set of reasonable defenses.

struct PuzzleDoc: Codable {
    var fen: String
    var sideToSolve: String
    var root: PuzzleNode
    var seq: Int?               // bumps each build so a new drill is detected
    var schema: Int?
    var hasPoisonedLine: Bool?        // this drill hides a human trap → warn "calculate deeply" (detected at build)
    var poisonedLineMoves: [BoardState.PoisonedMove]?   // the full trap line from `fen` — shown as a variation on reveal
}

/// A class so the tree can recurse (after / then reference PuzzleNode).
final class PuzzleNode: Codable {
    var kind: String            // "solve" | "mate" | "reply" | "done"
    var fen: String?
    var expectUci: String?      // solve nodes: the one required move
    var expectSan: String?
    var winPct: Double?
    var after: PuzzleNode?      // solve nodes: the opponent reply node
    var defenses: [Defense]?    // reply nodes: the opponent's reasonable tries
    var reason: String?         // done nodes: mate | converted | depth | …
    var mateIn: Int?            // mate nodes: forced mate in N
    var options: [Defense]?     // mate nodes: the mating move(s) — find any

    /// A node where the student is to move (must find a move).
    var isStudent: Bool { kind == "solve" || kind == "mate" }
}

struct Defense: Codable {
    var uci: String
    var san: String
    var then: PuzzleNode        // the position after this defense (a solve/done node)
}

extension PuzzleNode {
    /// Number of solve nodes under and including this one — the count of moves the whole tree
    /// forces you to find (progress denominator).
    var solveCount: Int {
        switch kind {
        case "solve": return 1 + (after?.solveCount ?? 0)
        case "mate":  return 1 + (options?.first?.then.solveCount ?? 0)
        case "reply": return (defenses ?? []).reduce(0) { $0 + $1.then.solveCount }
        default: return 0
        }
    }
}

/// What the app-driven walk reports for the coach to coach LIVE, serialized to the server's
/// `/input` as the input dict `read_input` returns. The app owns the walk (deterministic); each
/// event is a position worth a beat, grounded live (never a whole tree dumped into context).
enum DrillEvent {
    case started(lines: Int, fen: String)
    case solved(fen: String)
    case newLine(defense: String, fen: String)
    case finished
    case wrong(tried: String, fen: String)

    /// The wire keys are the coach's `read_input` contract (Python side), not model properties.
    var payload: [String: Any] {
        switch self {
        case let .started(lines, fen):
            return ["kind": "drill", "event": "started", "lines": lines, "fen": fen]
        case let .solved(fen):
            return ["kind": "drill", "event": "solved", "fen": fen]
        case let .newLine(defense, fen):
            return ["kind": "drill", "event": "new_line", "defense": defense, "fen": fen]
        case .finished:
            return ["kind": "none"]   // drill over → later turns classify OPEN
        case let .wrong(tried, fen):
            return ["kind": "drill_wrong", "tried": tried, "fen": fen]
        }
    }
}
