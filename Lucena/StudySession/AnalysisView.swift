import SwiftUI

/// The Analysis panel — the live engine's top lines (eval + PV) over an opening name, a game
/// header, and the move list. Matches the reference GUI in Lucena's print theme. The engine toggle
/// drives live analysis; `engineLines` stream in from the server (shown only when they match the
/// position on the board, so a stale line never lingers during navigation).
struct AnalysisView: View {
    let engineLines: EngineLines?
    let currentFen: String              // the position on the board (gate engine lines to it)
    @Binding var analysisOn: Bool
    let score: [ScoreMove]              // the game score — mainline whole, variations as asides
    let onSelect: (ScoreMove) -> Void

    /// ALL FOUR lines are always listed (owner 2026-07-26). What the chevron controls is the LENGTH
    /// of one line: a PV runs 12 plies and does not fit a panel column, so each row shows a single
    /// truncated line until its OWN caret opens it. Per PV, never a global collapse — you expand the
    /// line you are reading, and the other three stay where they were.
    @State private var expandedRanks: Set<Int> = []

    /// Engine lines only when they describe the position currently shown.
    private var lines: EngineLines? {
        guard analysisOn, let el = engineLines, el.fen == currentFen else { return nil }
        return el
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            engineHeader
            if let el = lines {
                // FOUR lines (owner 2026-07-26). The server searches MultiPV=4; the prefix is the
                // app's own guard so a differently-configured server can never stretch the panel.
                ForEach(el.lines.prefix(AnalysisStyle.maxLines)) { l in
                    engineRow(l, fen: el.fen)
                }
                if let opening = el.opening, !opening.isEmpty { openingRow(opening) }
            } else if let opening = engineLines?.opening, !opening.isEmpty {
                openingRow(opening)
            }
            MoveListView(score: score, onSelect: onSelect)
        }
    }

    // MARK: header

    private var engineHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            SquareSwitch(isOn: $analysisOn)
                .accessibilityLabel(Strings.StudySession.tabAnalysis)
            Text(Strings.StudySession.tabAnalysis)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            if let el = lines {
                Text(verbatim: "depth \(el.depth) · \(el.engine)")
                    .font(Theme.Typography.labelSmall)
                    .foregroundStyle(Theme.Palette.ink45)
            }
            Image(systemName: Theme.Symbol.gear)
                .imageScale(.small)
                .foregroundStyle(Theme.Palette.ink45)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.ink22).frame(height: 1) }
    }

    // MARK: engine line

    private func engineRow(_ line: EngineLine, fen: String) -> some View {
        let open = expandedRanks.contains(line.rank)
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(verbatim: AnalysisStyle.evalText(line.evalWhiteCp))
                .font(Theme.Typography.evalReadout)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.vertical, Theme.Spacing.xxs)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(Theme.Palette.paperDeep)
                .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
            // One line until this row's own caret opens it: a 12-ply PV wrapped by default
            // re-flowed the whole panel at every depth.
            Text(verbatim: AnalysisStyle.numberedPV(fen: fen, sans: line.pvSan))
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(open ? nil : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: open)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if open { expandedRanks.remove(line.rank) } else { expandedRanks.insert(line.rank) }
                }
            } label: {
                Image(systemName: Theme.Symbol.chevronDown)
                    .imageScale(.small)
                    .foregroundStyle(Theme.Palette.ink45)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Shorten this line" : "Show the whole line")
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func openingRow(_ name: String) -> some View {
        Text(verbatim: name)
            .font(Theme.Typography.moveLg)
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.ink22).frame(height: 1) }
    }
}

/// A SWITCH with square corners (owner 2026-07-26: "I asked you to implement a switch, not a
/// checkbox! Implement a switch!"). A real switch — a track the knob TRAVELS across, so the control
/// reads as on/off state rather than as a tick — drawn in the print theme: ink rule, square knob,
/// the track filling with ink when live. The macOS pill is the only thing rejected here, not the
/// affordance.
struct SquareSwitch: View {
    @Binding var isOn: Bool

    private let trackW: CGFloat = 30
    private let trackH: CGFloat = 16
    private let inset: CGFloat = 2

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? Theme.Palette.ink : Theme.Palette.paperDeep)
                    .frame(width: trackW, height: trackH)
                    .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
                Rectangle()
                    .fill(isOn ? Theme.Palette.paper : Theme.Palette.ink)
                    .frame(width: trackH - inset * 2, height: trackH - inset * 2)
                    .padding(.horizontal, inset)
            }
            .frame(width: trackW, height: trackH)
            .animation(.easeInOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

private enum AnalysisStyle {
    /// The panel shows the engine's top FOUR lines.
    static let maxLines = 4

    /// White-relative eval in pawns ("+0.23", "−0.50", "0.00"); a ceiled mate reads "+#"/"−#".
    static func evalText(_ cp: Int) -> String {
        if abs(cp) >= 1000 { return cp > 0 ? "+#" : "−#" }
        let pawns = Double(cp) / 100
        let sign = pawns > 0 ? "+" : (pawns < 0 ? "−" : "")
        return sign + String(format: "%.2f", abs(pawns))
    }

    /// A PV in numbered figurine notation from `fen`'s move number ("3… ♞f6 4. d3 ♝c5 …").
    static func numberedPV(fen: String, sans: [String]) -> String {
        let f = fen.split(separator: " ")
        var white = f.count > 1 ? f[1] == "w" : true
        var number = f.count > 5 ? (Int(f[5]) ?? 1) : 1
        var out = ""
        for (i, san) in sans.enumerated() {
            if white { out += "\(number). " } else if i == 0 { out += "\(number)… " }
            out += MoveListStyle.figurine(san) + " "
            if !white { number += 1 }
            white.toggle()
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
