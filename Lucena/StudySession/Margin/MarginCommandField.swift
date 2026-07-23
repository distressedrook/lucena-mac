import SwiftUI

/// The command field — a command palette in disguise (V1_LAYOUT.md). Takes
/// INSTRUCTIONS ("give me a puzzle", "what are my stats?"), never questions;
/// the placeholder cycles real commands so the affordance teaches the
/// grammar. Unwired: `onSubmit` receives the raw text and defaults to a
/// no-op — the intent registry lands with the API pass.
struct MarginCommandField: View {
    var hints: [String] = []
    var onSubmit: (String) -> Void = { _ in }

    @State private var text = ""
    @State private var hintIndex = 0
    @FocusState private var focused: Bool

    private let rotation = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(Theme.Glyph.prompt)
                .font(Theme.Typography.chatInput)
                .foregroundStyle(Theme.Palette.gold)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.chatInput)
                .foregroundStyle(Theme.Palette.ink)
                .focused($focused)
                .onSubmit(submit)
                .overlay(alignment: .leading) {
                    if text.isEmpty, !hints.isEmpty {
                        Text("Try: \u{201C}\(hints[hintIndex % hints.count])\u{201D}")
                            .font(Theme.Typography.chatInput)
                            .foregroundStyle(Theme.Palette.ink45)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                            .id(hintIndex)          // re-fade on each rotation
                    }
                }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onReceive(rotation) { _ in
            guard text.isEmpty, hints.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.4)) { hintIndex += 1 }
        }
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onSubmit(t)
        text = ""
    }
}
