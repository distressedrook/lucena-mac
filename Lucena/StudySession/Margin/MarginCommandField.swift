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
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.gold)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.move)          // the navigator's own type
                .foregroundStyle(Theme.Palette.ink)
                .focused($focused)
                .onSubmit(submit)
                .overlay(alignment: .leading) {
                    if text.isEmpty, !hints.isEmpty {
                        Text("Try: \u{201C}\(hints[hintIndex % hints.count])\u{201D}")
                            .font(Theme.Typography.move)
                            .foregroundStyle(Theme.Palette.ink45)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                            .id(hintIndex)          // re-fade on each rotation
                    }
                }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        // The navigator's twin (owner, with screenshot): same box — paper,
        // 1.5pt ink stroke, the same shadow lift — same inner metrics, so the
        // two read as one row across the bottom of the window.
        .background(Theme.Palette.paper)
        .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
        .shadow(color: Theme.Palette.ink.opacity(0.5), radius: 18, x: 0, y: 10)
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
