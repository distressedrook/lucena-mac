import SwiftUI

/// The settings popover — a hard-edged paper card with an offset ink shadow (matching the design's
/// `box-shadow: 3px 3px 0 ink`), holding the board/engine toggles. Floated by the screen under the
/// masthead gear; each pick performs its action and closes.
struct SettingsMenu: View {
    @Binding var flipped: Bool
    @Binding var engineOn: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(icon: Theme.Symbol.flip, title: Strings.StudySession.Menu.flipBoard,
                        divider: true) { flipped.toggle(); onClose() }
            SettingsRow(icon: Theme.Symbol.engine,
                        title: engineOn ? Strings.StudySession.Menu.disableEngine
                                        : Strings.StudySession.Menu.enableEngine,
                        divider: false) { engineOn.toggle(); onClose() }
        }
        .frame(minWidth: 178, alignment: .leading)
        .background(Theme.Palette.paper)
        .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
        .background(Rectangle().fill(Theme.Palette.ink).offset(x: 3, y: 3))   // hard offset shadow
        .fixedSize()
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: LocalizedStringKey
    let divider: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.gold)
                Text(title)
                    .font(Theme.Typography.label)
                    .tracking(Theme.Tracking.button)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: Theme.Spacing.lg)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(hovering ? Theme.Palette.paperDeep : Theme.Palette.paper)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if divider {
                    Rectangle().fill(Theme.Palette.ink.opacity(0.16)).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
