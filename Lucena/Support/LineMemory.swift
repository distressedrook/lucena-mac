import Foundation

/// WHAT THIS SESSION HAS SEEN, by position — the client half of the fen → analysis cache (owner
/// 2026-07-26: "can we also have front-end caching? while inside a session? I don't want it to make
/// calls each time a move is played").
///
/// Pure data, deliberately free of SwiftUI so it can be tested on its own (Tests/LineMemoryTests).
/// `StateStream` owns one and clears it whenever the conversation resets — this is memory of THIS
/// chat, not a durable store; the backend keeps the durable one.
struct LineMemory {
    /// Positions are keyed WITHOUT the move clocks, the same rule the backend caches by: the same
    /// board reached again is the same analysis, and a halfmove counter must not fragment it.
    static func key(_ fen: String) -> String {
        fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    private var byPosition: [String: EngineLines] = [:]
    private var order: [String] = []               // insertion order, for the bound
    private let max: Int

    init(max: Int = 256) { self.max = max }        // a long game's worth of positions

    func lines(for fen: String) -> EngineLines? { byPosition[Self.key(fen)] }

    /// DEEPEST WINS: a shallower frame for a position we have already taken deeper — the server
    /// republishing its own cache, or a restarted search — must not overwrite what we have.
    mutating func remember(_ v: EngineLines) {
        let k = Self.key(v.fen)
        if let have = byPosition[k], have.depth > v.depth { return }
        if byPosition[k] == nil {
            order.append(k)
            while order.count > max { byPosition.removeValue(forKey: order.removeFirst()) }
        }
        byPosition[k] = v
    }

    mutating func forgetAll() { byPosition.removeAll(); order.removeAll() }

    var count: Int { byPosition.count }
}
