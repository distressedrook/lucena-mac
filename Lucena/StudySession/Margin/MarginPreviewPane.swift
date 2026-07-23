import SwiftUI

/// Design-review harness for the v1 margin (V1_LAYOUT.md): the five margin
/// moments on fixtures (move 1 / book / card / noted / urgent), switchable with a small chrome picker at the top.
/// Lives behind the temporary "Margin" tab; deleted when the margin replaces
/// the beats column for real (the API pass).
struct MarginPreviewPane: View {
    private enum Moment: String, CaseIterable {
        case move1 = "MOVE 1"
        case theory = "BOOK"
        case quiet = "CARD"
        case noted = "NOTED"
        case urgent = "URGENT"

        var content: MarginContent {
            switch self {
            case .move1: .sampleMove1
            case .theory: .sampleTheory
            case .quiet: .sampleQuiet
            case .noted: .sampleNoted
            case .urgent: .sampleUrgent
            }
        }
    }

    @State private var moment: Moment = .quiet

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(Moment.allCases, id: \.self) { m in
                    Button { withAnimation(.easeInOut(duration: 0.15)) { moment = m } } label: {
                        Text(m.rawValue)
                            .font(Theme.Typography.labelSmall)
                            .tracking(Theme.Tracking.label)
                            .foregroundStyle(m == moment ? Theme.Palette.gold
                                                         : Theme.Palette.ink45)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            MarginColumnView(content: moment.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
