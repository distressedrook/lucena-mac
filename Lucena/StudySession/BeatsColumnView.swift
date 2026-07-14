import SwiftUI

/// The coach's voice — beats stream top-to-bottom, the active (newest) beat carries a blue
/// left-rule at full opacity, past beats fade behind a faint ink rule. A beat may carry an
/// inline "you" reply (the player's words, right-aligned).
struct BeatsColumnView<Footer: View>: View {
    let beats: [Beat]
    let footer: () -> Footer            // action buttons that flow at the END of the conversation

    init(beats: [Beat], @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.beats = beats
        self.footer = footer
    }

    var body: some View {
        // Chat/terminal scroll (macOS 14+): `defaultScrollAnchor(.bottom)` opens at the newest beat and
        // FOLLOWS new content while the reader is at the bottom, but leaves a scrolled-up reader exactly
        // where they are. It replaces a ScrollViewReader that fired `scrollTo` on a stack of timers on
        // every beat/text change — which fought an active drag (a `scrollTo` mid-drag can snap the view
        // to the top) and made the panel feel stuck. Let the framework own the anchor; don't chase it.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(beats) { beat in
                    BeatRow(beat: beat, active: beat.id == beats.last?.id)
                        .id(beat.id)
                }
                footer()                                        // Retry / show-me-the-trap, in-flow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, Theme.Spacing.xs)
        }
        .defaultScrollAnchor(.bottom)
    }
}

private struct BeatRow: View {
    let beat: Beat
    let active: Bool

    var body: some View {
        if beat.isYou {
            youBubble(beat.text)          // a standalone player turn — just the bubble, no coach rule
        } else {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(active ? Theme.Palette.coachBlue : Theme.Palette.ink18)
                    .frame(width: 2.5)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    label
                    BeatStyle.body(beat.segments)
                        .font(Theme.Typography.coachBody)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let you = beat.you {
                        youBubble(you)
                    }
                }
                .padding(.leading, Theme.Spacing.lg)
            }
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Palette.ink)
                .frame(width: Theme.Size.coachAvatar, height: Theme.Size.coachAvatar)
            Text(Strings.StudySession.coachName)
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.labelWide)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink70)
        }
    }

    private func youBubble(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
            Text(Strings.StudySession.youLabel)
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.labelWide)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink45)
            Text(text)
                .font(Theme.Typography.youBubble)
                .foregroundStyle(Theme.Palette.ink82)
                .padding(.vertical, 8)
                .padding(.horizontal, 13)
                .background(Theme.Palette.paperDeep)
                .overlay(Rectangle().stroke(Theme.Palette.ink.opacity(0.3), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, Theme.Spacing.xxs)
    }
}

// MARK: - presentation

private enum BeatStyle {
    /// Compose the beat's inline segments into one styled `Text`: default ink, `em` → blue
    /// italic, `mark` → red bold.
    static func body(_ segments: [Segment]) -> Text {
        segments.reduce(Text(verbatim: "")) { acc, seg in acc + run(seg) }
    }

    private static func run(_ seg: Segment) -> Text {
        switch seg.tone {
        case "em":
            return Text(seg.text).italic().foregroundColor(Theme.Palette.coachBlue)
        case "mark":
            return Text(seg.text).bold().foregroundColor(Theme.Palette.mistakeRed)
        default:
            return Text(seg.text)
        }
    }
}
