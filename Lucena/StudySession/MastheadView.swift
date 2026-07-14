import SwiftUI

/// A printed eval scale — a VERTICAL bar stuck to the board's left edge. White advantage fills up
/// from the bottom; a gold center tick marks parity. Fills the height it's given, so it matches the
/// board it sits beside.
struct EvalBarView: View {
    let evalFraction: Double

    init(fraction: Double) {
        self.evalFraction = min(1, max(0, fraction))
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Theme.Palette.ink)                    // black at the top
                Rectangle().fill(Theme.Palette.paper)                 // white fills up from the bottom
                    .frame(height: g.size.height * evalFraction)
            }
            .overlay { Rectangle().fill(Theme.Palette.gold.opacity(0.75)).frame(height: 1) }
            .border(Theme.Palette.ink, width: 1)
        }
    }
}

/// Turns the live board's eval (side-to-move POV, from the server) into the bar's white-relative
/// fill + readout. Neutral/blank before the coach has evaluated anything — never a stand-in number.
enum EvalPresentation {
    static func fraction(_ board: BoardState?) -> Double {
        guard let board, let stm = board.eval?.winPct else { return 0.5 }   // no eval → parity
        let whiteWin = board.sideToMove == "w" ? stm : 100 - stm
        return min(1, max(0, whiteWin / 100))
    }

    static func text(_ board: BoardState?) -> String {
        guard let board, let cp = board.eval?.cp else { return "" }
        let pawns = Double(board.sideToMove == "w" ? cp : -cp) / 100
        let sign = pawns > 0 ? "+" : (pawns < 0 ? "\u{2212}" : "")
        return sign + String(format: "%.1f", abs(pawns))
    }
}
