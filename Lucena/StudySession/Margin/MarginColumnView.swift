import SwiftUI

/// THE MARGIN — the v1 right column (mac-client/V1_LAYOUT.md). A book
/// margin, not a chat: it reads the CURRENT position only and re-renders as
/// the navigator cursor moves. Owner ruling: no resting state — the margin
/// always shows the move-1 epigraph, the in-book theory card, or cards (the
/// quiet position is itself a POSITION card). When a tactic fires the urgent
/// notice REPLACES everything, big and centered — a forced win IS the
/// position. No logos in the margin.
///
/// Unwired by design (owner: "build the UI, don't wire the APIs yet"):
/// callbacks are plumbed and default to no-ops; fixtures drive the previews.
struct MarginColumnView: View {
    let content: MarginContent
    var onCommand: (String) -> Void = { _ in }        // command box submit
    var onDrill: () -> Void = {}                      // the urgent card's button
    var onSquareTap: (String) -> Void = { _ in }      // future: arrows on the board
    var onDoorTap: (TheoryDoor) -> Void = { _ in }    // future: play the book move

    /// At most ONE card open (the ruling); salience upstream orders `cards`,
    /// so the first card starts expanded.
    @State private var expandedCard: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.none) {
            masthead
            if let urgent = content.urgent {
                // A forced win IS the position — the notice alone, centered.
                UrgentCardView(card: urgent, action: onDrill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if let epigraph = content.epigraph {
                            EpigraphView(epigraph: epigraph)
                        } else if let theory = content.theory {
                            TheoryCardView(card: theory, onDoorTap: onDoorTap)
                        } else {
                            if let rook = content.rookLine {
                                RookMarginaliaView(line: rook)
                            }
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                ForEach(content.cards) { card in
                                    MarginCardView(card: card,
                                                   expanded: expandedCard == card.id,
                                                   onToggle: {
                                                       withAnimation(.easeInOut(duration: 0.18)) {
                                                           expandedCard = expandedCard == card.id ? nil : card.id
                                                       }
                                                   },
                                                   onSquareTap: onSquareTap)
                                }
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)             // paper doesn't have scrollbars
                Spacer(minLength: Theme.Spacing.sm)
            }
            footer
        }
        .frame(width: Theme.Size.marginWidth, alignment: .leading)
        .onAppear { expandedCard = content.cards.first?.id }
        .onChange(of: content.cards.first?.id) { _, first in expandedCard = first }
    }

    // MARK: masthead — the opening names itself; status chrome; a hairline.

    @ViewBuilder private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text((content.masthead ?? "Lucena").uppercased())
                .font(Theme.Typography.masthead)
                .tracking(Theme.Tracking.labelWide)
                .foregroundStyle(Theme.Palette.ink82)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let status = content.statusLine {
                Text(status)
                    .font(Theme.Typography.labelSmall)
                    .tracking(Theme.Tracking.label)
                    .foregroundStyle(Theme.Palette.ink45)
            }
            Rectangle().fill(Theme.Palette.ink22).frame(height: 1)
        }
    }

    // MARK: footer — the command field alone (no logos in the margin).

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Rectangle().fill(Theme.Palette.ink22).frame(height: 1)
            MarginCommandField(hints: content.commandHints, onSubmit: onCommand)
        }
    }
}

// MARK: - Previews (fixtures; the four margin moments)

#Preview("quiet — position card") {
    MarginColumnView(content: .sampleQuiet)
        .padding(Theme.Spacing.lg).frame(height: 720).background(Theme.windowBackground)
}

#Preview("move 1 — epigraph") {
    MarginColumnView(content: .sampleMove1)
        .padding(Theme.Spacing.lg).frame(height: 720).background(Theme.windowBackground)
}

#Preview("in book — theory") {
    MarginColumnView(content: .sampleTheory)
        .padding(Theme.Spacing.lg).frame(height: 720).background(Theme.windowBackground)
}

#Preview("noted — plan open") {
    MarginColumnView(content: .sampleNoted)
        .padding(Theme.Spacing.lg).frame(height: 720).background(Theme.windowBackground)
}

#Preview("urgent — red card") {
    MarginColumnView(content: .sampleUrgent)
        .padding(Theme.Spacing.lg).frame(height: 720).background(Theme.windowBackground)
}
