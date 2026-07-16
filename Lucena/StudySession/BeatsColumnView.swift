import SwiftUI

/// The coach's voice — beats stream top-to-bottom, the active (newest) beat carries a blue
/// left-rule at full opacity, past beats fade behind a faint ink rule. A beat may carry an
/// inline "you" reply (the player's words, right-aligned).
struct BeatsColumnView<Footer: View>: View {
    let beats: [Beat]
    let onMoveTap: (String) -> Void     // tap a move chip → snap the board to that position (by fen)
    let footer: () -> Footer            // action buttons that flow at the END of the conversation

    init(beats: [Beat], onMoveTap: @escaping (String) -> Void = { _ in },
         @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.beats = beats
        self.onMoveTap = onMoveTap
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
                    BeatRow(beat: beat, active: beat.id == beats.last?.id, onMoveTap: onMoveTap)
                        .id(beat.id)
                        // Each beat animates IN, and the DIRECTION is attribution: the player's own
                        // turns slide from the right (like a sent message), the coach's from the left.
                        // A neutral move belongs to neither, so it must not slide from either side —
                        // sliding it in from the right would say "you played this" in motion, which is
                        // the same claim the text was just stopped from making. It fades in place.
                        .transition(BeatTransition.forBeat(beat))
                }
                footer()                                        // Retry / show-me-the-trap, in-flow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, Theme.Spacing.xs)
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// Which way a beat enters — the one place that answers "whose turn is this?" in motion.
///
/// A helper rather than a ternary at the call site because that ternary was the FOURTH copy of the
/// same attribution (the label, the alignment, the bubble, the transition), and it was the one that
/// kept saying "the player" after the other three had been fixed. Attribution is a property of the
/// beat; it belongs somewhere a new lane has to answer for itself.
private enum BeatTransition {
    static func forBeat(_ beat: Beat) -> AnyTransition {
        if beat.isNeutralMove { return .opacity }              // nobody's: no direction to come from
        return .opacity.combined(with: .move(edge: beat.isYou ? .trailing : .leading))
    }
}

private struct BeatRow: View {
    let beat: Beat
    let active: Bool
    var onMoveTap: (String) -> Void = { _ in }

    var body: some View {
        if beat.isNeutralMove, let notation = beat.notation, let fen = beat.fen {
            // A move on the shared analysis board. Checked BEFORE isYou: it is a "you" beat on the
            // wire (so old clients degrade to the bubble rather than mislabelling it as the coach),
            // but there is no "you" in freeform to attribute it to.
            neutralMove(notation, fen: fen)
        } else if beat.isYou {
            youBubble(beat.text, correct: beat.correct, move: beat.move, fen: beat.fen)
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
                        youBubble(you, correct: nil, move: nil, fen: nil)
                    }
                }
                .padding(.leading, Theme.Spacing.lg)
            }
        }
    }

    /// A played move with no speaker: centred, in the navigator's move font, reading as a move list
    /// rather than as anything anyone said. Tapping snaps the board there, like the "you" chip.
    private func neutralMove(_ notation: String, fen: String) -> some View {
        Text(verbatim: MoveListStyle.figurineNumbered(notation))
            .font(Theme.Typography.move)
            .foregroundStyle(Theme.Palette.ink70)
            .padding(.vertical, Theme.Spacing.xxs)
            .padding(.horizontal, Theme.Spacing.xs)
            .contentShape(Rectangle())
            .onTapGesture { onMoveTap(fen) }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Theme.Spacing.xxs)
    }

    private var label: some View {
        Text(Strings.StudySession.coachName)
            .font(Theme.Typography.labelSmall)
            .tracking(Theme.Tracking.labelWide)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.ink70)
    }

    private func youBubble(_ text: String, correct: Bool?, move: String?, fen: String?) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
            Text(Strings.StudySession.youLabel)
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.labelWide)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink45)
            HStack(spacing: Theme.Spacing.xs) {
                if let correct { verdictBadge(correct) }   // drill move → green check / red cross box
                if let move, let fen {                     // a played move → clickable navigator-style chip
                    Text(Strings.StudySession.played)
                        .font(Theme.Typography.coachBody).foregroundStyle(Theme.Palette.ink82)
                    moveChip(move) { onMoveTap(fen) }
                    if let sfx = suffix(of: text, after: move), !sfx.isEmpty {
                        Text(verbatim: sfx)
                            .font(Theme.Typography.coachBody).foregroundStyle(Theme.Palette.ink82)
                    }
                } else {
                    Text(text)                             // plain text, no bubble box; same size as the coach
                        .font(Theme.Typography.coachBody)
                        .foregroundStyle(Theme.Palette.ink82)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, Theme.Spacing.xxs)
    }

    /// The played move as a boxed chip — styled like the navigator's SELECTED move: a solid black box
    /// with the figurine glyph in light, in the navigator's move font. Tapping snaps the board there.
    private func moveChip(_ move: String, action: @escaping () -> Void) -> some View {
        Text(verbatim: MoveListStyle.figurine(move))
            .font(Theme.Typography.move)
            .foregroundStyle(Theme.Palette.paper)
            .padding(.vertical, Theme.Spacing.xxs)
            .padding(.horizontal, Theme.Spacing.xs)
            .background(Theme.Palette.ink)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    /// The echo text after the move token ("Played Qf3+ — takes the bishop" → " — takes the bishop").
    private func suffix(of text: String, after move: String) -> String? {
        guard let r = text.range(of: move) else { return nil }
        return String(text[r.upperBound...])
    }

    /// The drill verdict next to a played move: a solid square — green with a check (right) or red with
    /// a cross (wrong). Replaces the canned "That's right!" / "not quite" feedback beat.
    private func verdictBadge(_ correct: Bool) -> some View {
        Image(systemName: correct ? "checkmark" : "xmark")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.Palette.paper)
            .frame(width: 24, height: 24)
            .background(correct ? Theme.Palette.correctGreen : Theme.Palette.mistakeRed)
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
