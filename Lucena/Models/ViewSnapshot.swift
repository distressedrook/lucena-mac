import Foundation

/// The full display state the server mirrors and replays on resume (contract M-session-view): the
/// board the app is showing, the resolved line on screen, the whole variation forest, and the cursor.
/// Decoded from the `/state` `view` SSE event (server keys are snake_case → `convertFromSnakeCase`).
/// The app rebuilds its variation tree + cursor from this so a reopened session comes back exactly.
struct ViewSnapshot: Decodable {
    let seq: Int
    let fen: String
    let cursor: Int
    let inVariation: Bool
    let line: [Item]
    let tree: [Branch]

    /// One resolved move on screen: a mainline move (`kind == "main"`) or a sideline move
    /// (`kind == "variation"`); `branch` marks the first move of a sideline. The root "…" start block
    /// is `san == nil`.
    struct Item: Decodable {
        let san: String?
        let uci: String?
        let fen: String
        let kind: String
        let branch: Bool
    }

    /// A branch point: the position sidelines diverge from (`atFen`), its mainline ply if any, and
    /// each sideline (its first move + full continuation `line`).
    struct Branch: Decodable {
        let atFen: String
        let atPly: Int?
        let variations: [Variation]
    }

    struct Variation: Decodable {
        let uci: String
        let san: String
        let fen: String
        let line: [Move]
    }

    struct Move: Decodable {
        let uci: String
        let san: String
        let fen: String
    }
}
