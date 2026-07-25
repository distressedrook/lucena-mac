import SwiftUI

/// The game score — PGN-style numbered rows in figurine notation. The current/viewed move is
/// highlighted; tap a move to jump to that position.
///
/// Renders the GAME SCORE (`[ScoreMove]`), not the mainline ply list (2026-07-26, owner: "the
/// analysis section isn't supporting variations"). The mainline stays WHOLE and an open variation
/// appears as an indented aside beneath the move it replaces — the printed-score convention, and
/// what the owner's screenshot shows. Every move is clickable; each entry carries its own target,
/// because a mainline move and a sideline move mean different things to the board.
struct MoveListView: View {
    let score: [ScoreMove]
    let onSelect: (ScoreMove) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(MoveListStyle.rows(score)) { row in
                        if row.isVariation { variationRow(row) } else { moveRow(row) }
                    }
                }
            }
            .onChange(of: score.first(where: \.isCurrent)?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
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

    /// A MAINLINE row: the number in its gutter, then the white and black cells.
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

    /// A VARIATION row: indented under the move it branches from, behind a vertical rule, with the
    /// move number carried INLINE ("2… ♞f6") instead of in the gutter — the sideline is an aside on
    /// the game, so it must not line up with the game's own columns.
    private func variationRow(_ row: MoveRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.ink45)
                .frame(width: 1.5)
                .padding(.trailing, Theme.Spacing.sm)
            // No empty "…" cell here — an aside is prose, not a column: it starts at the rule and
            // carries its own number ("2… ♞f6"), which is why a sideline that opens on a black move
            // sits where a white move would.
            if let w = row.white { cell(w, inlineNumber: "\(w.move.number). ") }
            if let b = row.black {
                // "2… " only when the sideline OPENS on a black move; a black move that follows its
                // own white move in the same line needs no prefix.
                cell(b, inlineNumber: row.white == nil ? "\(b.move.number)… " : nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .padding(.leading, Theme.Size.moveNumberColumn + Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.md)
    }

    @ViewBuilder private func cell(_ entry: ScoreMove?, inlineNumber: String? = nil) -> some View {
        if let entry, let san = entry.move.san {
            let current = entry.isCurrent
            HStack(spacing: 0) {
                if let inlineNumber {
                    Text(verbatim: inlineNumber)
                        .font(Theme.Typography.move)
                        .foregroundStyle(Theme.Palette.ink45)
                }
                Button { onSelect(entry) } label: {
                    Text(verbatim: MoveListStyle.figurine(san))
                        .font(Theme.Typography.move)
                        .foregroundStyle(current ? Theme.Palette.paper : Theme.Palette.ink)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .background(current ? Theme.Palette.coachBlue : Color.clear)
                }
                .buttonStyle(.plain)
                .id(entry.id)
            }
            .frame(width: Theme.Size.moveCell, alignment: .leading)
        } else {
            Text(verbatim: "…")
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.ink45)
                .frame(width: Theme.Size.moveCell, alignment: .leading)
        }
    }
}

/// Notation helpers for the move list and the strip — figurine glyphs and PGN numbering. The score's
/// row grouping lives in GameScore.swift (pure, and tested there).
extension MoveListStyle {
    private static let glyphs: [Character: String] =
        ["K": "♚", "Q": "♛", "R": "♜", "B": "♝", "N": "♞"]

    /// SAN with the piece letter swapped for its figure (pawn moves + castling unchanged).
    static func figurine(_ san: String) -> String {
        guard let first = san.first, let g = glyphs[first] else { return san }
        return g + san.dropFirst()
    }

    /// One already-numbered move ("1.Nf3", "1...c5") in the app's own figurine style: "1. ♞f3",
    /// "1… c5".
    ///
    /// The BACKEND owns the numbering (it has the position; the beat carries only the rendered
    /// string), but the app owns how a move LOOKS — the spacing and the "…" here match `numbered`
    /// above, so the neutral lane reads like the move list rather than like a wire payload. Plain
    /// `figurine` cannot do this alone: it maps only the FIRST character, so behind a number prefix
    /// the piece letter never becomes a glyph and "1.Nf3" renders as-is.
    static func figurineNumbered(_ notation: String) -> String {
        guard let r = notation.range(of: #"^\d+\.{1,3}"#, options: .regularExpression) else {
            return figurine(notation)            // no prefix we recognise — render it verbatim
        }
        let prefix = notation[notation.startIndex..<r.upperBound]
        let san = figurine(notation[r.upperBound...].trimmingCharacters(in: .whitespaces))
        let number = prefix.prefix(while: \.isNumber)
        return prefix.hasSuffix("...") ? "\(number)… \(san)" : "\(number). \(san)"
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


}
