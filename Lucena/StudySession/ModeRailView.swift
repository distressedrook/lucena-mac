import SwiftUI

enum RailMode: CaseIterable, Hashable {
    case study, map, library

    var title: LocalizedStringKey {
        switch self {
        case .study: return Strings.StudySession.railStudy
        case .map: return Strings.StudySession.railMap
        case .library: return Strings.StudySession.railLibrary
        }
    }
}

/// The mode rail — logo, the three modes (gold bar marks the active one), and the live session list.
struct ModeRailView: View {
    let selected: RailMode
    var sessions: [SessionInfo] = []
    var currentSession: String?
    var onNewSession: () -> Void = {}
    var onResumeSession: (String) -> Void = { _ in }
    var loading: Bool = false          // server/snapshot still coming up → shimmer the list, hide New
    let onSelect: (RailMode) -> Void

    private static let maxRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .bottom, spacing: 4) {
                // The rook reads as the "L" — "ucena" completes the wordmark.
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: Theme.Size.logo)
                Text("ucena")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.bottom, 3)   // sit the baseline on the rook's foot
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Theme.Spacing.lg)

            ForEach(RailMode.allCases, id: \.self) { mode in
                RailItem(title: mode.title, active: mode == selected) { onSelect(mode) }
            }

            Text(Strings.StudySession.recentSessions)
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.labelWide)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink45)
                .padding(.horizontal, 16)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xs)

            if loading {
                ForEach(0..<3, id: \.self) { _ in
                    ShimmerBar(width: 128, height: 14)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                }
            } else if sessions.isEmpty {
                Text(Strings.StudySession.noSessions)
                    .font(Theme.Typography.labelSmall)
                    .foregroundStyle(Theme.Palette.ink45)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
            } else {
                ForEach(sessions.prefix(Self.maxRows)) { s in
                    RecentRow(name: s.name, meta: Self.metaLabel(s.updatedAt),
                              active: s.id == currentSession) { onResumeSession(s.id) }
                }
            }

            if !loading {   // New session only once everything's loaded
                NewSessionButton(action: onNewSession)
                    .padding(.top, Theme.Spacing.xs)
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.lg)
        .frame(width: Theme.Size.rail)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.paperDeep)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Palette.ink).frame(width: 1.5)
        }
    }

    /// A session's last-active date, "mmm d" (e.g. "jul 7") — grounded in its transcript mtime.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static func metaLabel(_ updatedAt: Double) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: updatedAt)).lowercased()
    }
}

private struct RailItem: View {
    let title: LocalizedStringKey
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.label)
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(active ? Theme.Palette.ink : Theme.Palette.ink45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .background(active ? Theme.Palette.paper : .clear)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(active ? Theme.Palette.gold : .clear)
                        .frame(width: 3)
                }
        }
        .buttonStyle(.plain)
    }
}

/// Starts a fresh coaching session (a new Claude Code session id) — sits under the recent list.
private struct NewSessionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: Theme.Symbol.plus)
                    .font(Theme.Typography.labelSmall)
                Text(Strings.StudySession.newSession)
                    .font(Theme.Typography.label)
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.Palette.ink70)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.leading, 14)
            .padding(.trailing, 16)
        }
        .buttonStyle(.plain)
    }
}

/// One session in the rail — its display name (or "Untitled" fallback) and last-active date. Tap to
/// resume it. The current session carries the gold marker.
private struct RecentRow: View {
    let name: String?
    let meta: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                title
                    .font(Theme.Typography.youBubble)
                    .foregroundStyle(active ? Theme.Palette.ink : Theme.Palette.ink82)
                    .lineLimit(1)
                Text(verbatim: meta)
                    .font(Theme.Typography.labelSmall)
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.ink45)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .background(active ? Theme.Palette.paper : .clear)
            .overlay(alignment: .leading) {
                Rectangle().fill(active ? Theme.Palette.gold : .clear).frame(width: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private var title: Text {
        if let name, !name.isEmpty { return Text(verbatim: name) }
        return Text(Strings.StudySession.untitledSession)
    }
}
