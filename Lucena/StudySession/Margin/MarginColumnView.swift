import SwiftUI

/// THE MARGIN — the v1 right column (mac-client/V1_LAYOUT.md). A book
/// margin, not a chat: it reads the CURRENT position only and re-renders as
/// the navigator cursor moves. Three salience states (resting / noted /
/// urgent) plus the two book phases (move-1 epigraph, in-book theory), all
/// derived from which fields of `MarginContent` are populated.
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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let urgent = content.urgent {
                        restingBlock(compact: true)
                        UrgentCardView(card: urgent, action: onDrill)
                    } else if content.rookLine != nil || !content.cards.isEmpty {
                        notedBlock
                    } else if let theory = content.theory {
                        TheoryCardView(card: theory, onDoorTap: onDoorTap)
                    } else if let epigraph = content.epigraph {
                        EpigraphView(epigraph: epigraph)
                    } else {
                        restingBlock(compact: false)
                    }
                }
                .padding(.top, Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)                 // paper doesn't have scrollbars
            Spacer(minLength: Theme.Spacing.sm)
            footer
        }
        .frame(width: Theme.Size.marginWidth, alignment: .leading)
        .onAppear { expandedCard = content.cards.first?.id }
        .onChange(of: content.cards.first?.id) { _, first in expandedCard = first }
    }

    // MARK: masthead — the opening names itself; a hairline under it.

    @ViewBuilder private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text((content.masthead ?? "Lucena").uppercased())
                .font(Theme.Typography.masthead)
                .tracking(Theme.Tracking.labelWide)
                .foregroundStyle(Theme.Palette.ink82)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Theme.Palette.ink22).frame(height: 1)
        }
    }

    // MARK: resting — always-true quiet reads; the margin is never empty.

    @ViewBuilder private func restingBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(content.restingLines) { line in
                switch line.register {
                case .chrome:
                    Text(line.text)
                        .font(Theme.Typography.label)
                        .tracking(Theme.Tracking.label)
                        .foregroundStyle(Theme.Palette.ink45)
                case .prose:
                    Text(line.text)
                        .font(Theme.Typography.restingProse)
                        .foregroundStyle(Theme.Palette.ink55)
                }
            }
        }
        if !compact {
            // Confident book-margin whitespace: the idle rook watches the
            // board, and the emptiness reads as "nothing needs your attention".
            VStack(spacing: Theme.Spacing.sm) {
                RookAvatarView(pose: .idle, size: Theme.Size.rookIdle)
                if let hint = content.commandHints.first {
                    Text("Try: \u{201C}\(hint)\u{201D}")
                        .font(Theme.Typography.epigraphCredit)
                        .foregroundStyle(Theme.Palette.ink45)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xxxl)
        }
    }

    // MARK: noted — the rook's one-liner + the card stack, one open.

    @ViewBuilder private var notedBlock: some View {
        restingBlock(compact: true)
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

    // MARK: footer — the rook beside the command field, above nothing else.

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Rectangle().fill(Theme.Palette.ink22).frame(height: 1)
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                RookAvatarView(pose: pose(for: content.rookLine?.tone),
                               size: Theme.Size.rookAvatar)
                MarginCommandField(hints: content.commandHints, onSubmit: onCommand)
            }
        }
    }

    private func pose(for tone: RookLine.Tone?) -> RookAvatarView.Pose {
        switch tone {
        case .praise: .praise
        case .correct: .correct
        case .teach: .teach
        case nil: .idle
        }
    }
}

// MARK: - Previews (fixtures; the five margin moments)

#Preview("resting") {
    MarginColumnView(content: .sampleResting)
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

#Preview("urgent — drill offer") {
    MarginColumnView(content: .sampleUrgent)
        .padding(Theme.Spacing.lg).frame(height: 720).background(Theme.windowBackground)
}
