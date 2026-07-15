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

    init() {
        Self.registerBundledFonts()
        let stream = StateStream(baseURL: Self.backend)
        _stateStream = State(initialValue: stream)
        // The live loop goes UP the same socket the state streams down.
        _coachBridge = State(initialValue: CoachBridge(baseURL: Self.backend, sendUp: { msg in
            Task { @MainActor in stream.send(msg) }
        }))
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
            StudySessionScreen()
                .environment(\.stateStream, stateStream)
                .environment(\.coachBridge, coachBridge)
                .frame(minWidth: Theme.Size.windowMin.width, minHeight: Theme.Size.windowMin.height)
                .preferredColorScheme(.light)   // fixed paper-&-ink identity — never dark-adapt
                .task { stateStream.start() }
        }
        .defaultSize(width: Self.initialWindowSize.width, height: Self.initialWindowSize.height)
        .windowResizability(.contentSize)
    }
}
