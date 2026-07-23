import SwiftUI

// The margin's printed furniture (V1_LAYOUT.md): epigraph, theory card with
// labeled doors, collapsible cards, the rook's marginalia, the urgent notice.
// All ink-on-paper — hairlines and type, no fills, no rounded corners.

// MARK: - Epigraph (move 1 — the book opens)

struct EpigraphView: View {
    let epigraph: Epigraph

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\u{201C}\(epigraph.quote)\u{201D}")
                .font(Theme.Typography.epigraph)
                .foregroundStyle(Theme.Palette.ink82)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(epigraph.author)")
                .font(Theme.Typography.epigraphCredit)
                .foregroundStyle(Theme.Palette.ink55)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, Theme.Spacing.xl)
        .padding(.horizontal, Theme.Spacing.sm)
    }
}

// MARK: - Theory card (in book — idea + labeled doors)

struct TheoryCardView: View {
    let card: TheoryCard
    var onDoorTap: (TheoryDoor) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let idea = card.idea {
                Text(idea)
                    .font(Theme.Typography.cardBody)
                    .foregroundStyle(Theme.Palette.ink82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !card.doors.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("WHERE THIS GOES")
                        .font(Theme.Typography.label)
                        .tracking(Theme.Tracking.label)
                        .foregroundStyle(Theme.Palette.ink45)
                    ForEach(card.doors) { door in
                        Button { onDoorTap(door) } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Text(door.san)
                                    .font(Theme.Typography.moveLg)
                                    .foregroundStyle(Theme.Palette.ink)
                                    .frame(width: Theme.Size.moveNumberColumn * 1.5,
                                           alignment: .leading)
                                Text(door.variation ?? "sideline")
                                    .font(Theme.Typography.cardBody)
                                    .foregroundStyle(door.variation == nil
                                                     ? Theme.Palette.ink45
                                                     : Theme.Palette.ink70)
                                Spacer(minLength: Theme.Spacing.xs)
                                if let pct = door.typicalPct {
                                    Text("\(pct)%")
                                        .font(Theme.Typography.label)
                                        .foregroundStyle(Theme.Palette.ink45)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Collapsible card (facts / plans …)

struct MarginCardView: View {
    let card: MarginCard
    let expanded: Bool
    var onToggle: () -> Void = {}
    var onSquareTap: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: onToggle) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(Theme.Glyph.play)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.gold)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(card.title.uppercased() + (card.count.map { " (\($0))" } ?? ""))
                        .font(Theme.Typography.label)
                        .tracking(Theme.Tracking.label)
                        .foregroundStyle(Theme.Palette.ink70)
                    Spacer(minLength: Theme.Spacing.none)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(card.sections) { section in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            if let heading = section.heading {
                                Text(heading)
                                    .font(Theme.Typography.cardHeading)
                                    .foregroundStyle(Theme.Palette.coachBlue)
                            }
                            ForEach(section.rows) { row in
                                CardRowView(row: row, onSquareTap: onSquareTap)
                            }
                        }
                    }
                }
                .padding(.leading, Theme.Spacing.md)
                .overlay(alignment: .leading) {     // a book's marginal rule
                    Rectangle().fill(Theme.Palette.ink18).frame(width: 1)
                }
            }
        }
    }
}

private struct CardRowView: View {
    let row: CardRow
    var onSquareTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            Text(row.text)
                .font(Theme.Typography.cardBody)
                .foregroundStyle(Theme.Palette.ink82)
                .fixedSize(horizontal: false, vertical: true)
            if !row.moves.isEmpty || !row.squares.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    if !row.moves.isEmpty {
                        Text(row.moves.joined(separator: " "))
                            .font(Theme.Typography.cardMove)
                            .foregroundStyle(Theme.Palette.coachBlue)
                    }
                    ForEach(row.squares, id: \.self) { sq in
                        Button { onSquareTap(sq) } label: {
                            Text(sq)
                                .font(Theme.Typography.squareTag)
                                .foregroundStyle(Theme.Palette.ink70)
                                .padding(.horizontal, Theme.Spacing.xxs)
                                .padding(.vertical, Theme.Spacing.hair)
                                .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Rook marginalia (the coach's one-liner)

struct RookMarginaliaView: View {
    let line: RookLine

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Text(Theme.Glyph.play)
                .font(Theme.Typography.label)
                .foregroundStyle(accent)
            Text(line.text)
                .font(Theme.Typography.marginalia)
                .foregroundStyle(Theme.Palette.coachBlue)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)                       // the hard budget — marginalia, not paragraphs
        }
    }

    private var accent: Color {
        switch line.tone {
        case .praise: Theme.Palette.correctGreen
        case .teach: Theme.Palette.gold
        case .correct: Theme.Palette.mistakeRed
        }
    }
}

// MARK: - Urgent card (tactic / drill offer — loud but typographic)

struct UrgentCardView: View {
    let card: UrgentCard
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ornamentRule
            Text(card.mark)
                .font(Theme.Typography.studyMark)
                .foregroundStyle(Theme.Palette.mistakeRed)
            Text(card.text.uppercased())
                .font(Theme.Typography.studyCaption)
                .tracking(Theme.Tracking.labelWide)
                .foregroundStyle(Theme.Palette.ink82)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(card.buttonTitle.uppercased())
                    .font(Theme.Typography.label)
                    .tracking(Theme.Tracking.label)
                    .foregroundStyle(Theme.Palette.mistakeRed)
                    .padding(.bottom, Theme.Spacing.hair)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.Palette.mistakeRed).frame(height: 1)
                    }
            }
            .buttonStyle(.plain)
            ornamentRule
        }
        .frame(maxWidth: .infinity)
    }

    /// The printed section-break: a short centered rule, the way a book sets
    /// off a study from the text around it.
    private var ornamentRule: some View {
        Rectangle()
            .fill(Theme.Palette.ink22)
            .frame(width: Theme.Spacing.xxl, height: 1)
    }
}
