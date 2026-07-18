import SwiftUI

/// The chat-input pane at the foot of the beats column — the player's text channel to the
/// coach, replacing the embedded `claude` terminal. Typing here POSTs one turn to the local
/// ADK/Gemini runner (`CoachBridge.sendTurn`); the coach's reply arrives as beats over `/state`
/// in the panel above. Compact (a bar, not a half-screen pane), so the beats get the room.
struct ChatInputPaneView: View {
    let maxHeight: CGFloat            // ½ of the right column — the pane grows up to this as you type
    let session: String?             // the coach session id (nil while it resolves)
    let coach: CoachBridge?
    var loading: Bool = false        // app warm-up (server/session) → disable input until ready
    /// Raised while a turn is in flight, so the screen can show the "coach is thinking" state
    /// (replaces the old transcript-watcher signal).
    @Binding var sending: Bool
    var onEngage: () -> Void = {}    // fired the moment the player starts typing → dismiss the starter tips

    @Environment(\.stateStream) private var stream
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var minHeight: CGFloat { maxHeight / 2 }   // ¼ of the column — the resting height

    private var canSend: Bool {
        !sending && !loading && session != nil
        && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...40)
                .font(Theme.Typography.coachBody)            // same as the chat bubbles
                .foregroundStyle(Theme.Palette.ink)
                .focused($focused)
                .disabled(loading || session == nil)
                .onSubmit(send)
                .onChange(of: text) { _, t in if !t.isEmpty { onEngage() } }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(verbatim: sending ? "Coach is thinking…" : "Ask your coach…")
                            .font(Theme.Typography.coachBody)
                            .foregroundStyle(Theme.Palette.ink.opacity(0.35))
                            .allowsHitTesting(false)
                    }
                }
            Button(action: send) {
                Image(systemName: sending ? "circle.dotted" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Theme.Palette.coachBlue : Theme.Palette.ink.opacity(0.25))
                    .symbolEffect(.pulse, isActive: sending)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Hug the text: rest at the ¼ minimum, grow with content up to the ½ maximum (then the field
        // scrolls). `fixedSize` stops the frame from greedily filling to the max when it's empty.
        .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.Palette.paper)                     // light chat surface, not a dark terminal
        .overlay(Rectangle().stroke(Theme.Palette.ink.opacity(0.3), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }                     // tap anywhere in the pane to type
        .onAppear { focused = true }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending, !loading, let session, let coach else { return }
        text = ""
        sending = true
        // Show it the instant it's sent, don't wait for the server: render the "you" bubble locally
        // under a nonce, send that same nonce up, and let the server's persisted echo reconcile back.
        let clientId = UUID().uuidString
        stream?.pushLocalYouBeat(t, clientId: clientId)
        Task {
            _ = await coach.sendTurn(text: t, sessionId: session, clientId: clientId)
            await MainActor.run { sending = false; focused = true }
        }
    }
}
