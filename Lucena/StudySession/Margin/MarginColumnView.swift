import SwiftUI

/// THE MARGIN — JSON-inspection mode (owner, 2026-07-23). The column shows
/// the plans layer's artifacts verbatim: the PRE-VERIFY sheet JSON the
/// moment the rolls land, replaced by the POST-VERIFY JSON when the verify
/// gate finishes. The former card UI (epigraph/theory/cards/urgent) lives
/// in git history with the backend's card builder.
struct MarginColumnView: View {
    let content: MarginContent
    var onCommand: (String) -> Void = { _ in }        // command box submit

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.none) {
            if let status = content.statusLine {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(status)
                        .font(Theme.Typography.labelSmall)
                        .tracking(Theme.Tracking.label)
                        .foregroundStyle(content.plansPending
                                         ? Theme.Palette.gold : Theme.Palette.ink45)
                    Rectangle().fill(Theme.Palette.ink22).frame(height: 1)
                }
            }
            if let text = content.raw {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(Theme.Typography.terminal)
                        .foregroundStyle(Theme.Palette.ink82)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .scrollIndicators(.never)             // paper doesn't have scrollbars
            } else {
                Spacer()                              // rolls in flight — bare paper
            }
            MarginCommandField(onSubmit: onCommand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // fill the pane we're given
    }
}

#Preview("pre-verify — pending") {
    MarginColumnView(content: MarginContent(
        statusLine: "PRE-VERIFY · VERIFYING…",
        raw: "{\n  \"schema\": \"lucena-plans/sheet@1\",\n  \"phase\": \"middlegame\"\n}",
        plansPending: true))
        .padding(Theme.Spacing.lg).frame(width: 360, height: 720).background(Theme.windowBackground)
}

#Preview("rolling — bare paper") {
    MarginColumnView(content: MarginContent(statusLine: "ROLLING…", plansPending: true))
        .padding(Theme.Spacing.lg).frame(width: 360, height: 720).background(Theme.windowBackground)
}
