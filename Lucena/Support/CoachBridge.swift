import Foundation

/// The app→server channel. The live coaching loop (turn / explain / position / view / input) goes
/// UP the same WebSocket the state streams down — `sendUp` forwards to `StateStream.send`. Session
/// lifecycle is REST. (Drill adjudication `/move` + `/analyze` + activity/reset are a backend
/// follow-up — the tools.py → engine-gRPC rewrite — and stay REST here for now.)
final class CoachBridge: Sendable {
    private let baseURL: URL
    private let sendUp: @Sendable ([String: Any]) -> Void   // -> StateStream.send (up the WS)

    init(baseURL: URL, sendUp: @escaping @Sendable ([String: Any]) -> Void) {
        self.baseURL = baseURL
        self.sendUp = sendUp
    }

    // -- live loop (up the WebSocket) --------------------------------------

    /// Drive ONE coaching turn. `text` = the player's typed message. The coach's beats stream back
    /// down the WS while the turn runs. Fire-and-forget over the socket.
    @discardableResult
    func sendTurn(text: String?, sessionId: String) async -> Bool {
        var m: [String: Any] = ["type": "turn"]
        if let text, !text.isEmpty { m["text"] = text }
        sendUp(m)
        return true
    }

    /// The on-demand "Why?" path: ask why `move` was right/wrong from `fen`. The explanation arrives
    /// as a beat over the WS.
    @discardableResult
    func explain(fen: String, move: String?, correct: Bool?, sessionId: String) async -> Bool {
        var m: [String: Any] = ["type": "explain", "fen": fen]
        if let move { m["move"] = move }
        if let correct { m["correct"] = correct }
        sendUp(m)
        return true
    }

    /// Report the position the board is currently SHOWING, so the coach grounds "what about this?"
    /// in the live board.
    func setBoardPosition(_ fen: String) async {
        sendUp(["type": "position", "fen": fen])
    }

    /// Report the app's FULL display state (resolved line, variation forest, cursor) so the server
    /// mirrors what the user sees and replays it on resume.
    func setView(_ snapshot: [String: Any]) async {
        var m = snapshot
        m["type"] = "view"
        sendUp(m)
    }

    /// Submit a played move (freeform, non-drill).
    func submitMove(_ uci: String, fen: String) async {
        await submit(["kind": "move", "uci": uci, "fen": fen])
    }

    /// Tell the server the player solved the whole drill (so the next turn is a grounded closing).
    func drillSolved(fen: String) async {
        await submit(["kind": "drill_solved", "fen": fen])
    }

    /// Submit an arbitrary structured input dict verbatim (stored for the orchestrator's read_input).
    func submit(_ payload: [String: Any]) async {
        sendUp(["type": "input", "data": payload])
    }

    // -- session lifecycle (REST) ------------------------------------------

    /// The durable session id, owned by the backend (GET auto-provisions one on first use).
    func currentSessionId() async -> String? {
        let req = URLRequest(url: baseURL.appendingPathComponent("session"))
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["session_id"] as? String
    }

    /// Start a new session — the BACKEND mints the id, makes it active (it also pushes reset + a clean
    /// snapshot over the WS), and returns it for us to adopt. Returns nil if the server didn't answer.
    func newSession() async -> String? {
        var req = URLRequest(url: baseURL.appendingPathComponent("session/new"))
        req.httpMethod = "POST"
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["session_id"] as? String
    }

    /// Make `id` the current session (server-persisted) — used when resuming an existing session.
    func setSessionId(_ id: String) async {
        var req = URLRequest(url: baseURL.appendingPathComponent("session"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["session_id": id])
        _ = try? await URLSession.shared.data(for: req)
    }

    // -- drill / analysis (REST; backend follow-up) ------------------------

    /// Toggle live engine analysis for the on-screen position. (Backend `/analyze` follow-up.)
    func setAnalysis(on: Bool, fen: String) async {
        await post("analyze", ["on": on, "fen": fen])
    }

    /// Push a raw played move for drill adjudication. (Backend `/move` follow-up.)
    @discardableResult
    func playMove(_ uci: String, fen: String) async -> MoveResult {
        var req = URLRequest(url: baseURL.appendingPathComponent("move"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["uci": uci, "fen": fen])
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return MoveResult() }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(MoveResult.self, from: data)) ?? MoveResult()
    }

    /// Pop the current rabbit-hole activity. (Backend `/activity` follow-up.)
    func popActivity() async { await post("activity", ["op": "pop"]) }

    /// Reset the board to the starting position. (Backend `/reset` follow-up.)
    func resetToStart() async { await post("reset", [:]) }

    private func post(_ path: String, _ body: [String: Any]) async {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
