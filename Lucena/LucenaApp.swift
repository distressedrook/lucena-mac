import SwiftUI
import AppKit
import CoreText

/// Lucena — the native macOS surface. It owns 100% of the visual UI and renders off the live state
/// the backend streams over the WebSocket (`/ws`). A thin client: it sends the player's input up the
/// socket and renders the board / beats the backend pushes down. The backend + engine are run
/// separately (the app connects to them); no local process is spawned.
@main
struct LucenaApp: App {
    /// The backend base URL. The WebSocket is `ws://…/ws` (StateStream derives it); REST is `…/session`.
    static let backend = URL(string: "http://127.0.0.1:8766")!

    private static var initialWindowSize: CGSize {
        NSScreen.main?.visibleFrame.size ?? Theme.Size.windowDefault
    }

    @State private var stateStream: StateStream
    @State private var coachBridge: CoachBridge
    @State private var authClient: AuthClient

    init() {
        Self.registerBundledFonts()
        let auth = AuthClient(baseURL: Self.backend)
        _authClient = State(initialValue: auth)
        // The token is read through a closure, never captured: the socket reconnects for the life of
        // the app, so a value taken here would be whatever existed at launch — stale the moment the
        // user signs in or out.
        let stream = StateStream(baseURL: Self.backend,
                                 token: { auth.token },          // nonisolated: safe to read off-main
                                 onRejected: { auth.rejected() })
        _stateStream = State(initialValue: stream)
        // The live loop goes UP the same socket the state streams down.
        _coachBridge = State(initialValue: CoachBridge(
            baseURL: Self.backend,
            sendUp: { msg in Task { @MainActor in stream.send(msg) } },
            token: { auth.token },
            // A 401 on ANY REST route means the token is dead. Same destination as the socket's own
            // refusal: drop it and show the login, rather than leave the app looking signed in while
            // every action silently no-ops.
            onRejected: { Task { @MainActor in auth.rejected() } }))
    }

    /// Register the bundled Lora faces (SIL OFL) so `Font.custom("Lora", …)` resolves. Done in code so
    /// it works regardless of how the app bundle lays out resources.
    private static func registerBundledFonts() {
        for name in ["Lora", "Lora-Italic"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Only a 401 from the backend puts up the login. Auth is optional server-side
                // (LUCENA_REQUIRE_AUTH), so a local single-user run must not be made to sign in to
                // itself — we ASK rather than assume. `.unknown` means we haven't heard yet (or the
                // backend is down), which is not a credentials problem: stay on the board and let the
                // socket's own reconnect handle it.
                if authClient.state == .signedOut {
                    LoginScreen()
                } else {
                    StudySessionScreen()
                        .task { stateStream.start() }
                }
            }
            // Tear the stream down the moment the login session ends — a revoked token
            // (`rejected()`) or a sign-out. Bound to the STATE, not to either caller: both routes end
            // here, and a future sign-out button cannot forget to do it.
            //
            // The `.task { stateStream.start() }` above does NOT cover this. SwiftUI cancels that task
            // when the view goes away, but `start()` spawns an UNSTRUCTURED Task, so cancelling the
            // `.task` does not touch it — the loop lives on, parked in `await ws.receive()`, on a
            // socket that is still authenticated as the user who just left.
            .onChange(of: authClient.state) { _, state in
                if state == .signedOut { stateStream.stop() }
            }
            .environment(\.stateStream, stateStream)
            .environment(\.coachBridge, coachBridge)
            .environment(\.authClient, authClient)
            .frame(minWidth: Theme.Size.windowMin.width, minHeight: Theme.Size.windowMin.height)
            .preferredColorScheme(.light)   // fixed paper-&-ink identity — never dark-adapt
            .task { await authClient.refresh() }
        }
        .defaultSize(width: Self.initialWindowSize.width, height: Self.initialWindowSize.height)
        .windowResizability(.contentSize)
    }
}
