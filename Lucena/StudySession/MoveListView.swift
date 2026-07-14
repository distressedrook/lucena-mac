import SwiftUI

/// The game score — PGN-style numbered rows in figurine notation. The current/viewed ply is
/// highlighted; tap a move to jump to that position. Pure render of `plies` (ply 0 = start).
struct MoveListView: View {
    let plies: [Ply]
    let currentIndex: Int              // the ply being viewed (highlighted)
    let onSelect: (Int) -> Void        // jump to a ply index

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(MoveListStyle.rows(plies), id: \.number) { row in
                        moveRow(row)
                    }
                }
            }
            .onChange(of: currentIndex) { _, i in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(Strings.StudySession.gameWhite).foregroundStyle(Theme.Palette.ink)
            Text(verbatim: "—").foregroundStyle(Theme.Palette.ink45)
            Text(Strings.StudySession.gameBlack).foregroundStyle(Theme.Palette.ink)
        }
        .font(Theme.Typography.moveLg)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.ink22).frame(height: 1) }
    }

    private func moveRow(_ row: MoveRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(row.number).")
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.ink45)
                .frame(width: Theme.Size.moveNumberColumn, alignment: .leading)
            cell(row.white)
            cell(row.black)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .padding(.horizontal, Theme.Spacing.md)
    }

    @ViewBuilder private func cell(_ ply: Ply?) -> some View {
        if let ply, let san = ply.san {
            Button { onSelect(ply.n) } label: {
                Text(verbatim: MoveListStyle.figurine(san))
                    .font(Theme.Typography.move)
                    .foregroundStyle(ply.n == currentIndex ? Theme.Palette.paper : Theme.Palette.ink)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .background(ply.n == currentIndex ? Theme.Palette.coachBlue : Color.clear)
            }
            .buttonStyle(.plain)
            .id(ply.n)
            .frame(width: Theme.Size.moveCell, alignment: .leading)
        } else {
            Text(verbatim: "…")
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.ink45)
                .frame(width: Theme.Size.moveCell, alignment: .leading)
        }
    }
}

/// A move-list row: the move number and its (up to two) plies.
struct MoveRow { let number: Int; let white: Ply?; let black: Ply? }

/// Presentation for the move list — row grouping from FENs, and figurine notation.
enum MoveListStyle {
    private static let glyphs: [Character: String] =
        ["K": "♚", "Q": "♛", "R": "♜", "B": "♝", "N": "♞"]

    /// SAN with the piece letter swapped for its figure (pawn moves + castling unchanged).
    static func figurine(_ san: String) -> String {
        guard let first = san.first, let g = glyphs[first] else { return san }
        return g + san.dropFirst()
    }

    /// A variation line as PGN-numbered figurine text, e.g. "18… ♝a6 19. b4" — numbers derived from
    /// each node's resulting fen (fullmove ticks after Black; the mover is the side NOT to move).
    static func numbered(_ nodes: [VarNode]) -> String {
        var out: [String] = []
        for (i, n) in nodes.enumerated() {
            let f = n.fen.split(separator: " ")
            let full = f.count > 5 ? Int(f[5]) ?? 1 : 1
            let whiteMoved = (f.count > 1 ? f[1] : "w") == "b"
            let num = whiteMoved ? full : full - 1
            let fig = figurine(n.san)
            if whiteMoved { out.append("\(num). \(fig)") }
            else if i == 0 { out.append("\(num)… \(fig)") }
            else { out.append(fig) }
        }
        return out.joined(separator: " ")
    }

    /// A run of `LineMove`s as PGN-numbered figurine text — e.g. "18… ♚g8 19. ♛xe8+". Skips the root
    /// "…" block and derives numbers from each move's fen. Used for the popover's "← parent" line.
    static func numberedLine(_ moves: [LineMove]) -> String {
        var out: [String] = []
        for (i, m) in moves.enumerated() {
            guard m.san != nil || m.uci != nil else { continue }
            let fig = figurine(m.san ?? m.uci ?? "…")
            if m.whiteMoved { out.append("\(m.number). \(fig)") }
            else if i > 0 && moves[i - 1].whiteMoved { out.append(fig) }        // pairs under its white move
            else { out.append("\(m.number)… \(fig)") }
        }
        return out.joined(separator: " ")
    }

    /// Group plies (ply 0 = start) into numbered rows. Each ply's move number + color come from the
    /// position it was played in — the previous ply's FEN — so a black-to-move start reads "1… ".
    static func rows(_ plies: [Ply]) -> [MoveRow] {
        guard plies.count > 1 else { return [] }
        var out: [MoveRow] = []
        for i in 1 ..< plies.count {
            let ply = plies[i]
            let f = plies[i - 1].fen.split(separator: " ")
            let color = f.count > 1 ? String(f[1]) : "w"
            let number = f.count > 5 ? (Int(f[5]) ?? out.count + 1) : out.count + 1
            if color == "w" {
                out.append(MoveRow(number: number, white: ply, black: nil))
            } else if let last = out.last, last.number == number, last.black == nil {
                out[out.count - 1] = MoveRow(number: number, white: last.white, black: ply)
            } else {
                out.append(MoveRow(number: number, white: nil, black: ply))
            }
        }
        return out
    }
}
