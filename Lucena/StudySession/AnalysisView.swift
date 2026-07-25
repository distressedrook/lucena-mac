import SwiftUI

/// The Analysis panel — the live engine's top lines (eval + PV) over an opening name, a game
/// header, and the move list. Matches the reference GUI in Lucena's print theme. The engine toggle
/// drives live analysis; `engineLines` stream in from the server (shown only when they match the
/// position on the board, so a stale line never lingers during navigation).
struct AnalysisView: View {
    let engineLines: EngineLines?
    let currentFen: String              // the position on the board (gate engine lines to it)
    @Binding var analysisOn: Bool
    let plies: [Ply]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    /// Engine lines only when they describe the position currently shown.
    private var lines: EngineLines? {
        guard analysisOn, let el = engineLines, el.fen == currentFen else { return nil }
        return el
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            engineHeader
            if let el = lines {
                ForEach(el.lines) { line in engineRow(line, fen: el.fen) }
                if let opening = el.opening, !opening.isEmpty { openingRow(opening) }
            } else if let opening = engineLines?.opening, !opening.isEmpty {
                openingRow(opening)
            }
            MoveListView(plies: plies, currentIndex: currentIndex, onSelect: onSelect)
        }
    }

    // MARK: header

    private var engineHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Toggle("", isOn: $analysisOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
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
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(verbatim: AnalysisStyle.evalText(line.evalWhiteCp))
                .font(Theme.Typography.evalReadout)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.vertical, Theme.Spacing.xxs)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(Theme.Palette.paperDeep)
                .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
            Text(verbatim: AnalysisStyle.numberedPV(fen: fen, sans: line.pvSan))
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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

private enum AnalysisStyle {
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
