import SwiftUI

/// The chat-input pane at the foot of the beats column — the player's text channel to the
/// coach, replacing the embedded `claude` terminal. Typing here POSTs one turn to the local
/// ADK/Gemini runner (`CoachBridge.sendTurn`); the coach's reply arrives as beats over `/state`
/// in the panel above. Compact (a bar, not a half-screen pane), so the beats get the room.
struct ChatInputPaneView: View {
    let maxHeight: CGFloat            // kept for call-site symmetry; the bar is a fixed compact height
    let session: String?             // the coach session id (nil while it resolves)
    let coach: CoachBridge?
    var loading: Bool = false        // app warm-up (server/session) → disable input until ready
    /// Raised while a turn is in flight, so the screen can show the "coach is thinking" state
    /// (replaces the old transcript-watcher signal).
    @Binding var sending: Bool

    @Environment(\.stateStream) private var stream
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !sending && !loading && session != nil
        && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(Theme.Typography.chatInput)
                    .foregroundStyle(Theme.Palette.terminalFg)
                    .focused($focused)
                    .disabled(loading || session == nil)
                    .onSubmit(send)
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text(verbatim: sending ? "Coach is thinking…" : "Ask your coach…")
                                .font(Theme.Typography.chatInput)
                                .foregroundStyle(Theme.Palette.terminalFg.opacity(0.4))
                                .allowsHitTesting(false)
                        }
                    }
                Button(action: send) {
                    Image(systemName: sending ? "circle.dotted" : "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? Theme.Palette.coachBlue
                                                 : Theme.Palette.terminalFg.opacity(0.3))
                        .symbolEffect(.pulse, isActive: sending)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(height: 96)
        .background(Theme.Palette.terminalBg)
        .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
        .onAppear { focused = true }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending, !loading, let session, let coach else { return }
        text = ""
        sending = true
        Task {
            _ = await coach.sendTurn(text: t, sessionId: session)
            await MainActor.run { sending = false; focused = true }
        }
    }

    private var titleBar: some View {
        let live = stream?.connected ?? false
        return HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(Theme.Palette.gold).frame(width: 9, height: 9)
            Text(verbatim: "Coach")
                .font(Theme.Typography.labelSmall)
                .foregroundStyle(Theme.Palette.terminalFg.opacity(0.7))
            Spacer()
            Circle().fill(live ? Theme.Palette.coachBlue : Theme.Palette.ink45)
                .frame(width: 6, height: 6)
            Text(live ? Strings.StudySession.Terminal.statusLive
                      : Strings.StudySession.Terminal.statusOffline)
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.terminalFg.opacity(0.6))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(Theme.Palette.ink)
    }
}
