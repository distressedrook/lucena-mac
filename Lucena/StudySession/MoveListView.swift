import SwiftUI

/// The game score — PGN-style numbered rows in figurine notation. The current/viewed move is
/// highlighted; tap a move to jump to that position.
///
/// Renders the SHOWN LINE (`[LineMove]`), not the mainline ply list (2026-07-26, owner: "the
/// analysis section isn't supporting variations"). That is the same unified mainline-plus-variation
/// line the navigator strip draws, so stepping into a "what if" is visible here and clickable here;
/// indices are indices into that line, which is what the screen's one jump handler takes.
struct MoveListView: View {
    let line: [LineMove]
    let cursor: Int                    // the move being viewed (highlighted)
    let onSelect: (Int) -> Void        // jump to a move, by index into `line`

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(MoveListStyle.rows(line)) { row in
                        moveRow(row)
                    }
                }
            }
            .onChange(of: cursor) { _, i in
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
            // A variation's first move carries a gold rule, the same divergence mark the navigator
            // strip draws — without it a sideline reads as if it were the game.
            Rectangle()
                .fill(row.isBranch ? Theme.Palette.gold : Color.clear)
                .frame(width: 2)
                .padding(.trailing, Theme.Spacing.xxs)
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

    @ViewBuilder private func cell(_ entry: (index: Int, move: LineMove)?) -> some View {
        if let entry, let san = entry.move.san {
            let current = entry.index == cursor
            Button { onSelect(entry.index) } label: {
                Text(verbatim: MoveListStyle.figurine(san))
                    .font(Theme.Typography.move)
                    .foregroundStyle(current ? Theme.Palette.paper : Theme.Palette.ink)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .background(current ? Theme.Palette.coachBlue : Color.clear)
            }
            .buttonStyle(.plain)
            .id(entry.index)
            .frame(width: Theme.Size.moveCell, alignment: .leading)
        } else {
            Text(verbatim: "…")
                .font(Theme.Typography.move)
                .foregroundStyle(Theme.Palette.ink45)
                .frame(width: Theme.Size.moveCell, alignment: .leading)
        }
    }
}

/// A move-list row: the move number and its (up to two) moves, each carrying its index into the
/// shown line. `isBranch` marks a row that opens a variation.
struct MoveRow: Identifiable {
    let id: String
    let number: Int
    let white: (index: Int, move: LineMove)?
    let black: (index: Int, move: LineMove)?
    let isBranch: Bool
}

/// Presentation for the move list — row grouping from FENs, and figurine notation.
enum MoveListStyle {
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

    /// Group the shown line into numbered rows. Number and color come from each move's OWN resulting
    /// fen (LineMove.number / .whiteMoved), which is what makes this work identically for a mainline
    /// ply and for a variation move played at any depth — a black-to-move start reads "1… ", and a
    /// sideline picks up at its real move number rather than being renumbered from 1.
    static func rows(_ line: [LineMove]) -> [MoveRow] {
        var out: [MoveRow] = []
        for (i, m) in line.enumerated() {
            guard m.san != nil else { continue }        // the root "…" block is not a move
            // The navigator's "?" placeholder (the drill's parked wrong tries) is an affordance,
            // not a played move: it has no uci and no resulting position of its own, so numbering
            // it from the solve fen would print a move that was never made. The strip renders it
            // unnumbered; the game score simply doesn't carry it.
            guard !(m.uci == nil && m.san == "?") else { continue }
            let entry = (index: i, move: m)
            if m.whiteMoved {
                out.append(MoveRow(id: m.id, number: m.number, white: entry, black: nil,
                                   isBranch: m.isBranch))
            } else if let last = out.last, last.number == m.number, last.black == nil {
                out[out.count - 1] = MoveRow(id: last.id, number: last.number, white: last.white,
                                             black: entry, isBranch: last.isBranch || m.isBranch)
            } else {
                out.append(MoveRow(id: m.id, number: m.number, white: nil, black: entry,
                                   isBranch: m.isBranch))
            }
        }
        return out
    }
}
