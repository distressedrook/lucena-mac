import Foundation

/// The app→server channel. The live coaching loop (turn / explain / position / view / input) goes
/// UP the same WebSocket the state streams down — `sendUp` forwards to `StateStream.send`. Session
/// lifecycle is REST. (Drill adjudication `/move` + `/analyze` + activity/reset are a backend
/// follow-up — the tools.py → engine-gRPC rewrite — and stay REST here for now.)
final class CoachBridge: Sendable {
    private let baseURL: URL
    private let token: @Sendable () -> String?
    private let sendUp: @Sendable ([String: Any]) -> Void   // -> StateStream.send (up the WS)
    private let onRejected: @Sendable () -> Void            // -> AuthClient.rejected (401 on any route)

    /// `token` is a closure for the same reason as StateStream's: a value captured at init would be
    /// whatever existed at launch, and go stale on sign-in/out or revocation.
    /// `onRejected` fires on a 401 from ANY REST route — see `perform`.
    init(baseURL: URL, sendUp: @escaping @Sendable ([String: Any]) -> Void,
         token: @escaping @Sendable () -> String? = { nil },
         onRejected: @escaping @Sendable () -> Void = {}) {
        self.baseURL = baseURL
        self.token = token
        self.sendUp = sendUp
        self.onRejected = onRejected
    }

    // -- live loop (up the WebSocket) --------------------------------------

    /// Drive ONE coaching turn. `text` = the player's typed message. The coach's beats stream back
    /// down the WS while the turn runs. Fire-and-forget over the socket.
    @discardableResult
    func sendTurn(text: String?, sessionId: String, clientId: String? = nil) async -> Bool {
        var m: [String: Any] = ["type": "turn"]
        if let text, !text.isEmpty { m["text"] = text }
        // The nonce the client already rendered this message under (optimistic "you" beat). The server
        // stamps it on the persisted echo so the client can reconcile the two — see pushLocalYouBeat.
        if let clientId { m["client_id"] = clientId }
        sendUp(m)
        return true
    }

    /// The on-demand "Why?" path: ask why `move` was right/wrong from `fen`. The explanation arrives
    /// as a beat over the WS.
    @discardableResult
    func explain(fen: String, move: String?, correct: Bool?, sessionId: String) async -> Bool {
        var m: [String: Any] = ["type": "explain", "fen": fen]
        if let move { m["uci"] = move }          // the held wrong move's uci; backend reads msg["uci"]
        if let correct { m["correct"] = correct }
        sendUp(m)
        return true
    }

    /// Point THIS socket at `id` — the server moves our subscription and replays that chat's snapshot.
    ///
    /// Required after minting or resuming a chat. The server's events are addressed to a chat's
    /// subscribers, not broadcast to every socket, so a REST call that changes the active chat is
    /// invisible to us until the socket itself moves: without this the new chat only appears on the
    /// next reconnect, because a fresh socket resolves the active chat on connect.
    func openChat(_ id: String) {
        sendUp(["type": "open_chat", "session_id": id])
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

    /// The player clicked Continue on a solved branch — walk the next sibling defence. The server does
    /// the deferred backtrack and streams the new board + beats.
    func continueBranch() {
        sendUp(["type": "continue"])
    }

    /// Submit an arbitrary structured input dict verbatim (stored for the orchestrator's read_input).
    /// The margin's content for one position (deterministic, engine-free
    /// server-side) — nil on any failure; the margin keeps its last content.
    func margin(fen: String, sessionId: String?, live: Bool = false) async -> Data? {
        var req = request("margin", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["fen": fen, "live": live]
        if let sessionId { body["session_id"] = sessionId }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if case .ok(let data) = await perform(req) { return data }
        return nil
    }

    func submit(_ payload: [String: Any]) async {
        sendUp(["type": "input", "data": payload])
    }

    /// Every REST request is built HERE, so the bearer cannot be forgotten on a route added later —
    /// the same reason the backend authenticates in middleware rather than per-route.
    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if let t = token() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return req
    }

    /// Every REST request is EXECUTED here, for the same reason it is built here: a 401 is not a
    /// per-route concern, and each call site handling it separately means the one added next month
    /// will not.
    ///
    /// Without this, a token revoked mid-session was invisible. Every call site swallowed its failure
    /// (`try?` → nil → a default), so the UI stayed on the board looking signed in while every action
    /// quietly did nothing — and `currentSessionId` returning nil sends the caller off to mint a
    /// LOCAL fallback id, so the app carries on writing into a session the server has never heard of.
    /// The recovery path was "hope the socket also happens to notice", which it did not (see
    /// StateStream.isAuthRefusal).
    ///
    /// A 401 and a transport failure are NOT the same answer, and collapsing them to nil was itself a
    /// bug: "the server is down" invites a local fallback, while "your token is dead" must not — the
    /// caller would build state against a session the server will never accept. See `Outcome`.
    private func perform(_ req: URLRequest) async -> Outcome {
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return .failed }
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            onRejected()
            return .rejected
        }
        return .ok(data)
    }

    /// What a REST call actually got back.
    ///
    /// `rejected` exists separately from `failed` because callers legitimately paper over `failed` —
    /// the backend restarts, the network blips, and falling back to a local session id so the user can
    /// keep moving is the right call. Doing that on a 401 is the opposite of right: the token is dead,
    /// the login is about to appear, and minting a local id means the app writes into a session the
    /// server never heard of and pushes it up a socket that is about to be torn down. Nothing is the
    /// correct action on a rejection, and nothing is only correct if a caller can TELL.
    enum Outcome {
        case ok(Data)
        case rejected      // 401 — the token is dead; the login is taking over. Do not fall back.
        case failed        // no answer (server down, network). A local fallback may be appropriate.

        var data: Data? { if case .ok(let d) = self { return d }; return nil }
        var isRejected: Bool { if case .rejected = self { return true }; return false }
    }

    // -- session lifecycle (REST) ------------------------------------------

    /// The durable session id, owned by the backend (GET auto-provisions one on first use).
    func currentSessionId() async -> String? {
        guard let data = await perform(request("session")).data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["session_id"] as? String
    }

    /// Start a new session — the BACKEND mints the id, makes it active (it also pushes reset + a clean
    /// snapshot over the WS), and returns it for us to adopt. Returns nil if the server didn't answer.
    /// Returns `.rejected` when the token is dead, so the caller does NOT fall back to a local id —
    /// see `Outcome`. `.failed` still means "server down", which a caller may paper over.
    func newSession() async -> SessionResult {
        let out = await perform(request("session/new", method: "POST"))
        if out.isRejected { return .rejected }
        guard let data = out.data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["session_id"] as? String
        else { return .failed }
        return .id(id)
    }

    enum SessionResult {
        case id(String)
        case rejected
        case failed
    }

    /// Make `id` the current session (server-persisted) — used when resuming an existing session.
    func setSessionId(_ id: String) async {
        var req = request("session", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["session_id": id])
        _ = await perform(req)
    }

    // -- drill / analysis (REST; backend follow-up) ------------------------

    /// Toggle live engine analysis for the on-screen position. (Backend `/analyze` follow-up.)
    func setAnalysis(on: Bool, fen: String) async {
        await post("analyze", ["on": on, "fen": fen])
    }

    /// Push a raw played move for drill adjudication. (Backend `/move` follow-up.)
    @discardableResult
    func playMove(_ uci: String, fen: String, clientId: String? = nil) async -> MoveResult {
        var req = request("move", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["uci": uci, "fen": fen]
        if let clientId { body["client_id"] = clientId }   // reconciles the optimistic "you played" bubble
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let data = await perform(req).data else { return MoveResult() }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(MoveResult.self, from: data)) ?? MoveResult()
    }

    /// Switch the in-view activity: reopen a saved activity by index (a card click), or `idx: 0` to
    /// return to the base conversation. The server replays that activity's board/beats/variations.
    func openActivity(_ idx: Int) async { await post("activity", ["op": "open", "idx": idx]) }

    /// Leave the current drill (the header's back button): the lesson goes `open` (resumable) and
    /// the chat drops back to freeform — the server confirms over the WS `mode` event.
    func leaveLesson() async { await post("lesson", ["op": "leave"]) }

    /// Reset the board to the starting position. (Backend `/reset` follow-up.)
    func resetToStart() async { await post("reset", [:]) }

    private func post(_ path: String, _ body: [String: Any]) async {
        var req = request(path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = await perform(req)
    }
}
