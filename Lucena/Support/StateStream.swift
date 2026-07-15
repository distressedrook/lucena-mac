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

    init(baseURL: URL) { self.baseURL = baseURL }

    /// Point at a (new) server URL and (re)start streaming.
    func connect(to url: URL) { baseURL = url; start() }

    func start() {
        task?.cancel()
        task = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        task?.cancel()
        task = nil
        connected = false
    }

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await stream(webSocketURL())
            } catch {
                connected = false; ready = false
                wsTask = nil
                try? await Task.sleep(for: .seconds(2))   // reconnect; the snapshot re-syncs
            }
        }
    }

    /// The live loop is now a WebSocket (`/ws`); scheme http→ws, https→wss.
    private func webSocketURL() -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("ws"), resolvingAgainstBaseURL: false)!
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        return comps.url!
    }

    private func stream(_ url: URL) async throws {
        let ws = URLSession.shared.webSocketTask(with: url)
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
            let message = try await ws.receive()
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

    private func applyBeats(_ data: Data) {
        guard let ev = try? decoder.decode(BeatsEvent.self, from: data) else { return }
        if let snapshot = ev.beats { beats = snapshot }            // snapshot-on-connect
        else if let appended = ev.appended { beats.append(contentsOf: appended) }  // delta
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
