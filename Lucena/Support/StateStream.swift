import Foundation
import Observation
import SwiftUI   // withAnimation — the stream is where UI state changes, so it owns the transitions

/// The live UI state, streamed from the MCP server's `/state` SSE feed (LLD-app §2). The app is
/// a client, not a file-poller: this subscribes, decodes the typed channel events (snapshot on
/// connect, then deltas), and publishes the current board / beats / analysis / turn for the views
/// to render. Reconnects on drop (the snapshot re-syncs). Main-actor isolated so every mutation
/// the views observe happens on the main thread.
@MainActor
@Observable
final class StateStream {
    private(set) var board: BoardState?
    private(set) var beats: [Beat] = []
    private(set) var analysis: PositionAnalysis?
    private(set) var turn: TurnState?
    private(set) var drill: PuzzleDoc?      // an active forcing-win tree for the app to walk
    private(set) var history: [Ply] = []    // the move line (ply 0 = start), for the navigator
    private(set) var engineLines: EngineLines?   // live analysis for the current position (transient)
    private(set) var coachStatus: String?        // "what the coach is doing" phase (transient, tool-grounded)
    private(set) var sessions: [SessionInfo] = []   // the rail's session list (live, pushed by the server)
    private(set) var currentSession: String?
    private(set) var view: ViewSnapshot?            // the app's persisted display state, replayed on resume
    private(set) var viewEpoch = 0                  // bumps on each `view` event → drives re-hydration
    private(set) var version = 0                    // P4b: the server's monotonic document version we're at
    private(set) var activityDepth = 1             // P5: activity-stack depth (1 = base, no breadcrumb)
    private(set) var activityKind = "conversation" // P5: the live (top) activity's kind
    private(set) var connected = false
    private(set) var ready = false        // the full initial snapshot has arrived → safe to reveal the UI

    private var baseURL: URL
    private var task: Task<Void, Never>?
    private var wsTask: URLSessionWebSocketTask?     // the live socket (input up, state down)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase   // server sends snake_case; models are camelCase
        return d
    }()

    /// `token` is a CLOSURE, not a value: the socket reconnects on its own for the life of the app,
    /// and a token captured once would be the one from launch — stale the moment the user signs in,
    /// signs out, or their token is revoked. Read it fresh on every connect.
    /// `onRejected` fires when the server closes the handshake 1008 (policy violation) — the token is
    /// dead, so the app must return to the login rather than reconnect-loop against a refusal.
    init(baseURL: URL, token: @escaping @Sendable () -> String? = { nil },
         onRejected: @escaping @MainActor () -> Void = {}) {
        self.baseURL = baseURL
        self.token = token
        self.onRejected = onRejected
    }

    private let token: @Sendable () -> String?
    private let onRejected: @MainActor () -> Void

    /// Point at a (new) server URL and (re)start streaming.
    func connect(to url: URL) { baseURL = url; start() }

    /// Bumps on every lifecycle boundary (start / stop). A frame decoded from a socket whose
    /// generation has passed is DROPPED — see `stream`.
    ///
    /// Cancellation alone cannot cover this. `await ws.receive()` may have already COMPLETED, with its
    /// continuation queued on the main actor behind `stop()`: the task is then cancelled and the state
    /// cleared, and the loop resumes anyway holding a frame from the previous login session and
    /// repopulates board/beats/sessions right after sign-out. `Task.isCancelled` is checked too, but it
    /// is not sufficient alone — the resumed continuation runs before the loop condition is re-tested.
    /// Safe unguarded: this class is @MainActor, so every touch of it is serialised.
    private var generation = 0

    func start() {
        task?.cancel()
        generation &+= 1
        let gen = generation
        task = Task { [weak self] in await self?.runLoop(gen) }
    }

    /// Stop streaming and forget everything this connection was showing.
    ///
    /// Cancelling `task` alone was not enough, and the gap was a real leak across a sign-out: the loop
    /// task can be parked in `await ws.receive()`, so the SOCKET has to be cancelled to break it —
    /// otherwise an already-authenticated socket stays alive after the user signs out, still receiving
    /// (and able to send) on the previous user's credentials. And a cancelled socket alone would still
    /// leave the last user's board, beats and session list sitting in memory for the next sign-in to
    /// inherit for a frame. State that belongs to a login session dies with it.
    func stop() {
        generation &+= 1          // anything already in flight from the old socket is now stale
        task?.cancel()
        task = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        connected = false
        ready = false
        board = nil
        beats = []
        analysis = nil
        turn = nil
        drill = nil
        history = []
        engineLines = nil
        coachStatus = nil
        sessions = []
        currentSession = nil
        view = nil
        version = 0
    }

    private func runLoop(_ gen: Int) async {
        while !Task.isCancelled && gen == generation {
            do {
                try await stream(webSocketURL(), gen)
            } catch {
                let refused = handshakeStatus.map(Self.isAuthRefusal) ?? false
                connected = false; ready = false
                wsTask = nil
                // The server refusing the handshake for a bad/absent token. Reconnecting cannot fix
                // that — it would spin forever against a refusal behind a frozen board — so hand it to
                // the login instead and stop.
                if refused {
                    await MainActor.run { onRejected() }
                    return
                }
                try? await Task.sleep(for: .seconds(2))   // reconnect; the snapshot re-syncs
            }
        }
    }

    /// The live loop is now a WebSocket (`/ws`); scheme http→ws, https→wss.
    private func webSocketURL() -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("ws"), resolvingAgainstBaseURL: false)!
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        // The token rides as a query param, not a header: a WS handshake cannot carry Authorization
        // from a browser, so the server reads `?token=` — and it authenticates BEFORE accepting, so a
        // bad one closes the handshake rather than leaving an unauthenticated socket alive.
        if let t = token() {
            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "token", value: t)]
        }
        return comps.url!
    }

    /// The HTTP status of the last handshake, when the socket never opened. See `isAuthRefusal`.
    private var handshakeStatus: Int?

    /// Did the server refuse this handshake on AUTH grounds?
    ///
    /// MEASURED against the real backend, not inferred. The backend rejects a socket BEFORE accept
    /// (`websocket.close(1008)`), and it is tempting to look for 1008 on the client — that is what the
    /// server sends and what the code used to check. It never arrives. A pre-accept close is an ASGI
    /// instruction to fail the HTTP UPGRADE, so uvicorn answers the handshake with **403** and the
    /// socket never exists to carry a close frame. URLSession reports `NSURLErrorDomain -1011`
    /// (badServerResponse) with `task.response` = 403. So the old check could not fire, ever: an
    /// expired token meant an infinite reconnect loop behind a frozen board, never the login screen.
    /// 401 is included because that is what the same middleware returns on the REST side; if the WS
    /// rejection is ever routed through it, this keeps working.
    private static func isAuthRefusal(_ status: Int) -> Bool { status == 403 || status == 401 }

    private func stream(_ url: URL, _ gen: Int) async throws {
        let ws = URLSession.shared.webSocketTask(with: url)
        handshakeStatus = nil
        ws.resume()
        wsTask = ws
        // Re-baseline the version on every (re)connect. A fresh socket always begins with a full
        // authoritative snapshot, and the server's version sequence restarts on a backend restart —
        // often LOWER than what we last saw. Without this reset the version guard would drop that
        // snapshot (and every delta after it) as "stale", silently freezing the app until the server
        // happened to climb back past our old number. A new connection is a clean slate.
        version = 0
        withAnimation(.easeInOut(duration: 0.3)) { connected = true }   // eases the warm-up → chat swap
        defer { if wsTask === ws { wsTask = nil } }
        // Each server→client frame is one JSON object `{type: <channel>, ...payload}`. Extract the
        // channel and hand the whole frame to the (unchanged) typed dispatch.
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await ws.receive()
            } catch {
                // Read the handshake status off the task BEFORE rethrowing: it is the only place the
                // refusal is visible, and it is gone once the task is released.
                handshakeStatus = (ws.response as? HTTPURLResponse)?.statusCode
                throw error
            }
            // The await above may have resumed AFTER a sign-out cleared everything. This frame belongs
            // to the login session that just ended; applying it would put the previous user's board and
            // beats back on screen.
            guard gen == generation else { return }
            let frame: String
            switch message {
            case .string(let s): frame = s
            case .data(let d):   frame = String(data: d, encoding: .utf8) ?? ""
            @unknown default:    frame = ""
            }
            guard let data = frame.data(using: .utf8),
                  let type = (try? decoder.decode(TypedFrame.self, from: data))?.type
            else { continue }
            dispatch(event: type, payload: frame)
        }
    }

    /// Send a client→server message up the live socket (`turn`/`explain`/`position`/`view`/`input`).
    func send(_ message: [String: Any]) {
        guard let ws = wsTask,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(text)) { _ in }
    }

    private struct TypedFrame: Decodable { var type: String }

    private func dispatch(event: String, payload: String) {
        guard let data = payload.data(using: .utf8) else { return }
        // Live analysis fires many times a second — animating it would thrash, so update it raw.
        if event == "engine_lines" {
            if let v = try? decoder.decode(EngineLines.self, from: data) { engineLines = v }
            return
        }
        // Everything else is a discrete UI change (a new beat, a repaint, a status). Mutate inside an
        // animation transaction so the views ease into it instead of snapping — the stream is the
        // single source of "smooth" for the whole screen.
        // P4b: apply deltas in version order — drop a delta older than the state we've already applied
        // (self-healing on the ordered stream; a reconnect re-snapshots). `reset`/`ready` carry no
        // meaningful order (a session switch restarts the version sequence), so they skip the guard.
        if event != "reset" && event != "ready",
           let v = (try? decoder.decode(VersionedEvent.self, from: data))?.version {
            if v < version { return }
            version = v
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            switch event {
            case "ready":    ready = true
            case "reset":    board = nil; beats = []; analysis = nil; drill = nil; turn = nil
                             history = []; engineLines = nil; coachStatus = nil; view = nil
                             version = 0; activityDepth = 1; activityKind = "conversation"
            case "activity": if let a = try? decoder.decode(ActivityEvent.self, from: data) {
                                 activityDepth = a.depth ?? 1; activityKind = a.kind ?? "conversation"
                             }
            case "status":   coachStatus = (try? decoder.decode(StatusEvent.self, from: data))?.text
            case "board":    if let v = try? decoder.decode(BoardState.self, from: data) { board = v }
            case "beats":    applyBeats(data)
            case "analysis": if let v = try? decoder.decode(PositionAnalysis.self, from: data) { analysis = v }
            case "turn":     if let v = try? decoder.decode(TurnState.self, from: data) { turn = v }
            case "tree":     if let v = try? decoder.decode(PuzzleDoc.self, from: data) { drill = v }
            case "tree_cleared": drill = nil
            case "history":  if let v = try? decoder.decode(MoveHistory.self, from: data) { history = v.plies }
            case "view":     if let v = try? decoder.decode(ViewSnapshot.self, from: data) { view = v; viewEpoch += 1 }
            case "sessions": if let v = try? decoder.decode(SessionList.self, from: data) {
                                 sessions = v.sessions; currentSession = v.current
                             }
            default: break
            }
        }
    }

    /// Append an app-authored beat (e.g. the "I didn't catch that" fallback when the coach ended a
    /// turn without speaking). Ephemeral — a server snapshot on reconnect replaces the beats. Uses an
    /// out-of-band `i` so it never collides with the server's sequential beat ids.
    func pushLocalBeat(_ text: String, tone: String = "correct") {
        let i = (beats.map(\.i).max() ?? 0) + 1_000_000
        beats.append(Beat(i: i, kind: "say", tone: tone, text: text))
    }

    /// Render the player's just-typed message IMMEDIATELY as a right-aligned "you" beat, before the
    /// server has seen it. `clientId` is the nonce the caller also sends up with the turn; the server
    /// persists the beat and echoes it back carrying the same id, and `applyBeats` reconciles the two
    /// into one so the message never appears twice. Out-of-band `i` until the server assigns the real
    /// one. Returns nothing — the reconciliation is by `clientId`, not by index.
    func pushLocalYouBeat(_ text: String, clientId: String) {
        let i = (beats.map(\.i).max() ?? 0) + 1_000_000
        var b = Beat(i: i, kind: "you", text: text)
        b.clientId = clientId
        beats.append(b)
    }

    /// Render the player's just-played BOARD move immediately as a "you played" bubble, before the
    /// server adjudicates. Carries the move chip + after-move `fen` (so it's clickable at once); the
    /// verdict badge and captured-piece detail are absent here and fill in when the server's echo of
    /// this same `clientId` reconciles (a drill can't know right/wrong until the backend says so).
    func pushLocalYouMoveBeat(_ text: String, move: String, fen: String,
                              correct: Bool? = nil, clientId: String) {
        let i = (beats.map(\.i).max() ?? 0) + 1_000_000
        var b = Beat(i: i, kind: "you", text: text)
        b.move = move
        b.fen = fen
        b.correct = correct     // the drill verdict, adjudicated locally (nil = freeform, no badge)
        b.clientId = clientId
        beats.append(b)
    }

    private func applyBeats(_ data: Data) {
        guard let ev = try? decoder.decode(BeatsEvent.self, from: data) else { return }
        if let snapshot = ev.beats { beats = snapshot }            // snapshot-on-connect (server wins)
        else if let appended = ev.appended {                       // delta
            for beat in appended {
                // Reconcile an optimistic "you" beat with the server's echo of it (same clientId):
                // replace in place so the message stays a single bubble instead of doubling.
                if let cid = beat.clientId, let idx = beats.firstIndex(where: { $0.clientId == cid }) {
                    beats[idx] = beat
                } else {
                    beats.append(beat)
                }
            }
        }
    }

    private struct BeatsEvent: Decodable {
        var beats: [Beat]?
        var appended: [Beat]?
    }

    private struct StatusEvent: Decodable { var text: String? }
    private struct VersionedEvent: Decodable { var version: Int? }
    private struct ActivityEvent: Decodable { var depth: Int?; var kind: String? }

    /// A disconnected stream preloaded with fixed state — for SwiftUI previews and the fidelity pass.
    static func stub(board: BoardState? = nil, beats: [Beat] = [],
                     analysis: PositionAnalysis? = nil) -> StateStream {
        let s = StateStream(baseURL: URL(string: "http://127.0.0.1:0")!)
        s.board = board; s.beats = beats; s.analysis = analysis
        s.ready = true   // previews show content, not the warm-up shimmer
        return s
    }
}
