import Foundation

/// A minimal FEN move applier for **local display feedback** only. It handles normal moves,
/// captures, castling, en passant, and auto-queen promotion, and flips the side to move. The app is
/// not a rules engine; the coach (with the real board core) re-derives the authoritative position.
///
/// Every FEN field is nonetheless produced FAITHFULLY — castling rights, en-passant target (emitted
/// on every double push, `lucena_core.board.Board.apply`'s `en_passant="fen"` contract), halfmove
/// clock, fullmove number. The optimistic FEN this returns is compared against the server's echo
/// (`displayedFen`), and it is the key for the opening-book/theory lookup: an approximated field
/// makes an in-book position miss theory and churns the loading highlights. Parity with the server
/// is pinned by Tests/ChessMoveApplyTests.swift.
enum ChessMove {
    /// Returns the display FEN after the move and the UCI string, or nil if the source square is
    /// empty / off-board.
    /// Does this move promote a pawn (a pawn reaching the last rank)? Used to pop the piece picker
    /// instead of silently auto-queening.
    static func isPromotion(_ fen: String, from: String, to: String) -> Bool {
        let parts = fen.split(separator: " ").map(String.init)
        guard !parts.isEmpty, let (ff, fr) = coord(from), let (_, tr) = coord(to) else { return false }
        guard let piece = parseBoard(parts[0])[fr][ff], piece == "P" || piece == "p" else { return false }
        return tr == 7 || tr == 0
    }

    static func apply(_ fen: String, from: String, to: String,
                      promotion: Character? = nil) -> (fen: String, uci: String)? {
        let parts = fen.split(separator: " ").map(String.init)
        guard !parts.isEmpty,
              let (ff, fr) = coord(from), let (tf, tr) = coord(to) else { return nil }
        var grid = parseBoard(parts[0])
        guard let piece = grid[fr][ff] else { return nil }

        let stm = parts.count > 1 ? parts[1] : "w"
        let isPawn = (piece == "P" || piece == "p")
        let white = piece.isUppercase
        var uci = from + to

        // Read the capture BEFORE mutating: a normal capture (destination
        // occupied) or an en-passant capture (a pawn stepping diagonally onto
        // an empty square). Both reset the halfmove clock below.
        let isEnPassant = isPawn && ff != tf && grid[tr][tf] == nil
        let isCapture = grid[tr][tf] != nil || isEnPassant

        // en passant: a pawn moving diagonally onto an empty square captures the pawn sitting on
        // the destination file, source rank.
        if isEnPassant {
            grid[fr][tf] = nil
        }
        grid[fr][ff] = nil
        if isPawn, tr == 7 || tr == 0 {          // promotion — to the chosen piece (default queen)
            let p = promotion ?? "Q"
            grid[tr][tf] = white ? Character(p.uppercased()) : Character(p.lowercased())
            uci += String(p).lowercased()
        } else {
            grid[tr][tf] = piece
        }
        // castling: the king steps two files -> bring the rook across.
        if piece == "K" || piece == "k", abs(tf - ff) == 2 {
            if tf == 6 { grid[fr][5] = grid[fr][7]; grid[fr][7] = nil }   // O-O
            if tf == 2 { grid[fr][3] = grid[fr][0]; grid[fr][0] = nil }   // O-O-O
        }

        // Castling RIGHTS must be maintained, not blanked — an in-book position
        // is keyed on the full FEN (placement+side+CASTLING+ep), so dropping
        // rights to "-" makes every opening miss the theory lookup and be read
        // as out-of-book (owner 2026-07-25: opening pawns lit up mid-theory).
        var rights = Set(parts.count > 2 ? parts[2] : "-"); rights.remove("-")
        func drop(_ cs: String) { cs.forEach { rights.remove($0) } }
        if piece == "K" { drop("KQ") }
        if piece == "k" { drop("kq") }
        // a rook leaving — or an enemy capturing a rook ON — a home corner
        // ends that side's right (an already-vacated corner is a no-op drop).
        for (f, r, right) in [(7, 0, "K"), (0, 0, "Q"), (7, 7, "k"), (0, 7, "q")] {
            if (piece == "R" || piece == "r"), ff == f, fr == r { drop(right) }
            if tf == f, tr == r { drop(right) }
        }
        let castle = ["K", "Q", "k", "q"].filter { rights.contains(Character($0)) }.joined()

        // en passant: a pawn's two-square push exposes the skipped square as the
        // ep target, emitted on EVERY double push whether or not a capture is
        // actually available. That is the server's contract — lucena_core's
        // Board.apply returns `fen(en_passant="fen")` (the cozy-chess
        // convention it preserves) — and our optimistic FEN is compared against
        // that echo, so 1.e4 must read `... b KQkq e3 0 1` here too or
        // `displayedFen` churns and the loading highlights drop.
        var ep = "-"
        if isPawn, abs(tr - fr) == 2 {
            ep = String(UnicodeScalar(UInt8(97 + tf))) + String((fr + tr) / 2 + 1)
        }

        // Halfmove clock: reset on a pawn move or any capture, else increment.
        // It MUST match the server's python-chess value — a stale hardcoded 0
        // was the "works a couple of turns then stops" churn (a quiet move made
        // the server report 1 while we still said 0, so `displayedFen` flipped
        // and the highlight gate `marginStages.first.fen == displayedFen` broke).
        let prevHalf = (parts.count > 4 ? Int(parts[4]) : nil) ?? 0
        let half = (isPawn || isCapture) ? 0 : prevHalf + 1

        let next = stm == "w" ? "b" : "w"
        // Carry the fullmove counter so variation move numbers are right (it ticks after Black moves).
        let full = (parts.count > 5 ? Int(parts[5]) : nil) ?? 1
        let nextFull = stm == "b" ? full + 1 : full
        return ("\(serialize(grid)) \(next) \(castle.isEmpty ? "-" : castle) \(ep) \(half) \(nextFull)", uci)
    }

    /// Standard algebraic notation for a (legal) move: piece letter, disambiguation, capture,
    /// destination, promotion, castling, and a check `+` / mate `#` suffix. For variation display —
    /// the mainline's SAN comes from the server. Falls back to UCI on a malformed input.
    static func san(_ fen: String, from: String, to: String, promotion: Character? = nil) -> String {
        let parts = fen.split(separator: " ").map(String.init)
        guard let (ff, fr) = coord(from), let (tf, tr) = coord(to), !parts.isEmpty else { return from + to }
        let grid = parseBoard(parts[0])
        guard let piece = grid[fr][ff] else { return from + to }
        let white = piece.isUppercase
        let upper = Character(piece.uppercased())
        let isPawn = upper == "P"
        let suffix = checkSuffix(fen, from: from, to: to)
        if upper == "K", abs(tf - ff) == 2 { return (tf == 6 ? "O-O" : "O-O-O") + suffix }
        let isCapture = grid[tr][tf] != nil || (isPawn && ff != tf)   // ep counts (diagonal pawn move)
        var s = ""
        if isPawn {
            if isCapture { s += String(UnicodeScalar(UInt8(97 + ff))) }
        } else {
            s += String(upper)
            s += disambiguation(grid, parts, piece: piece, white: white, ff: ff, fr: fr, tf: tf, tr: tr)
        }
        if isCapture { s += "x" }
        s += to
        if isPawn, tr == 7 || tr == 0 { s += "=" + String(promotion ?? "Q").uppercased() }
        return s + suffix
    }

    /// The minimal SAN disambiguator: if another same-type piece can also legally reach the target,
    /// add the mover's file (if unique), else its rank, else its full square.
    private static func disambiguation(_ grid: [[Character?]], _ parts: [String], piece: Character,
                                       white: Bool, ff: Int, fr: Int, tf: Int, tr: Int) -> String {
        let fen = parts.joined(separator: " ")
        var others: [(Int, Int)] = []
        for r in 0..<8 { for f in 0..<8 where (f, r) != (ff, fr) && grid[r][f] == piece {
            let sq = String(UnicodeScalar(UInt8(97 + f))) + String(r + 1)
            let dst = String(UnicodeScalar(UInt8(97 + tf))) + String(tr + 1)
            if isLegal(fen, from: sq, to: dst) { others.append((f, r)) }
        } }
        if others.isEmpty { return "" }
        if !others.contains(where: { $0.0 == ff }) { return String(UnicodeScalar(UInt8(97 + ff))) }
        if !others.contains(where: { $0.1 == fr }) { return String(fr + 1) }
        return String(UnicodeScalar(UInt8(97 + ff))) + String(fr + 1)
    }

    /// "+" if the move gives check, "#" if it's mate, "" otherwise.
    private static func checkSuffix(_ fen: String, from: String, to: String) -> String {
        guard let (nf, _) = apply(fen, from: from, to: to) else { return "" }
        let parts = nf.split(separator: " ").map(String.init)
        let g = parseBoard(parts[0])
        let oppWhite = (parts.count > 1 ? parts[1] : "b") == "w"
        guard let (kf, kr) = kingSquare(g, white: oppWhite) else { return "" }
        guard attacked(g, kf, kr, byWhite: !oppWhite) else { return "" }
        return anyLegalMove(nf, white: oppWhite) ? "+" : "#"
    }

    /// Does `white`'s side have ANY legal move in `fen`? (Used only for mate detection in SAN.)
    private static func anyLegalMove(_ fen: String, white: Bool) -> Bool {
        let parts = fen.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return false }
        let grid = parseBoard(parts[0])
        for r in 0..<8 { for f in 0..<8 {
            guard let p = grid[r][f], p.isUppercase == white else { continue }
            let src = String(UnicodeScalar(UInt8(97 + f))) + String(r + 1)
            for tr in 0..<8 { for tf in 0..<8 {
                let dst = String(UnicodeScalar(UInt8(97 + tf))) + String(tr + 1)
                if isLegal(fen, from: src, to: dst) { return true }
            } }
        } }
        return false
    }

    // MARK: FEN <-> grid (grid[rank 0..7 = rank1..8][file 0..7 = a..h])

    private static func coord(_ square: String) -> (Int, Int)? {
        let s = Array(square)
        guard s.count == 2, let fa = s[0].asciiValue, (97...104).contains(Int(fa)),
              let rank = s[1].wholeNumberValue, (1...8).contains(rank) else { return nil }
        return (Int(fa) - 97, rank - 1)   // (file, rank0)
    }

    private static func parseBoard(_ field: String) -> [[Character?]] {
        var grid = Array(repeating: Array<Character?>(repeating: nil, count: 8), count: 8)
        let ranks = field.split(separator: "/")
        for (i, rankStr) in ranks.enumerated() where i < 8 {
            let rank = 7 - i                 // ranks[0] is rank 8 -> grid[7]
            var file = 0
            for ch in rankStr {
                if let n = ch.wholeNumberValue { file += n; continue }
                if file < 8 { grid[rank][file] = ch }
                file += 1
            }
        }
        return grid
    }

    // MARK: legality (front-end rule enforcement — no server round-trip)

    /// True iff moving the piece on `from` to `to` is a LEGAL move for the side to move: correct
    /// piece movement, blocking, captures, castling, en passant, and the mover's king not left in
    /// check. `grid[rank0..7][file0..7]`, rank0 = rank 1.
    static func isLegal(_ fen: String, from: String, to: String) -> Bool {
        let parts = fen.split(separator: " ").map(String.init)
        guard let (ff, fr) = coord(from), let (tf, tr) = coord(to),
              !parts.isEmpty else { return false }
        let grid = parseBoard(parts[0])
        guard let piece = grid[fr][ff] else { return false }
        let white = piece.isUppercase
        let stm = parts.count > 1 ? parts[1] : "w"
        guard (stm == "w") == white else { return false }                 // must be your piece
        if let dest = grid[tr][tf], dest.isUppercase == white { return false }  // no self-capture
        let castling = parts.count > 2 ? parts[2] : "-"
        let ep = parts.count > 3 ? coord(parts[3]) : nil
        guard pseudoLegal(grid, ff, fr, tf, tr, piece: piece, white: white,
                          ep: ep, castling: castling) else { return false }
        var g = grid                                                       // apply, then king-safety
        applyOnGrid(&g, ff, fr, tf, tr, piece: piece, white: white, ep: ep)
        guard let (kf, kr) = kingSquare(g, white: white) else { return true }
        return !attacked(g, kf, kr, byWhite: !white)
    }

    private static func pseudoLegal(_ g: [[Character?]], _ ff: Int, _ fr: Int, _ tf: Int, _ tr: Int,
                                    piece: Character, white: Bool, ep: (Int, Int)?, castling: String) -> Bool {
        let df = tf - ff, dr = tr - fr
        switch Character(piece.uppercased()) {
        case "P":
            let dir = white ? 1 : -1, startRank = white ? 1 : 6
            if df == 0 && dr == dir && g[tr][tf] == nil { return true }     // push 1
            if df == 0 && dr == 2 * dir && fr == startRank
                && g[fr + dir][ff] == nil && g[tr][tf] == nil { return true }   // push 2
            if abs(df) == 1 && dr == dir {                                  // capture / en passant
                if let d = g[tr][tf], d.isUppercase != white { return true }
                if let ep, ep == (tf, tr) { return true }
            }
            return false
        case "N": return (abs(df), abs(dr)) == (1, 2) || (abs(df), abs(dr)) == (2, 1)
        case "B": return abs(df) == abs(dr) && df != 0 && clear(g, ff, fr, tf, tr)
        case "R": return (df == 0) != (dr == 0) && clear(g, ff, fr, tf, tr)
        case "Q": return ((abs(df) == abs(dr) && df != 0) || ((df == 0) != (dr == 0)))
            && clear(g, ff, fr, tf, tr)
        case "K":
            if max(abs(df), abs(dr)) == 1 { return true }
            if dr == 0 && abs(df) == 2 { return canCastle(g, ff, fr, kingside: df > 0,
                                                          white: white, castling: castling) }
            return false
        default: return false
        }
    }

    /// All squares strictly between (ff,fr) and (tf,tr) are empty (for sliding pieces).
    private static func clear(_ g: [[Character?]], _ ff: Int, _ fr: Int, _ tf: Int, _ tr: Int) -> Bool {
        let sf = (tf - ff).signum(), sr = (tr - fr).signum()
        var f = ff + sf, r = fr + sr
        while (f, r) != (tf, tr) {
            if g[r][f] != nil { return false }
            f += sf; r += sr
        }
        return true
    }

    private static func canCastle(_ g: [[Character?]], _ ff: Int, _ fr: Int, kingside: Bool,
                                  white: Bool, castling: String) -> Bool {
        let right: Character = white ? (kingside ? "K" : "Q") : (kingside ? "k" : "q")
        guard castling.contains(right), fr == (white ? 0 : 7), ff == 4 else { return false }
        let path = kingside ? [5, 6] : [1, 2, 3]                            // squares that must be empty
        for f in path where g[fr][f] != nil { return false }
        let through = kingside ? [4, 5, 6] : [4, 3, 2]                      // king can't pass through check
        for f in through where attacked(g, f, fr, byWhite: !white) { return false }
        return true
    }

    /// Move the piece on a grid copy (handles en-passant capture, castling rook, auto-queen) — enough
    /// to test the resulting king safety.
    private static func applyOnGrid(_ g: inout [[Character?]], _ ff: Int, _ fr: Int, _ tf: Int, _ tr: Int,
                                    piece: Character, white: Bool, ep: (Int, Int)?) {
        let isPawn = piece == "P" || piece == "p"
        if isPawn, ff != tf, g[tr][tf] == nil { g[fr][tf] = nil }          // en passant
        g[fr][ff] = nil
        if isPawn, tr == 7 || tr == 0 { g[tr][tf] = white ? "Q" : "q" } else { g[tr][tf] = piece }
        if (piece == "K" || piece == "k"), abs(tf - ff) == 2 {             // move the rook
            if tf == 6 { g[fr][5] = g[fr][7]; g[fr][7] = nil }
            if tf == 2 { g[fr][3] = g[fr][0]; g[fr][0] = nil }
        }
    }

    private static func kingSquare(_ g: [[Character?]], white: Bool) -> (Int, Int)? {
        let k: Character = white ? "K" : "k"
        for r in 0..<8 { for f in 0..<8 where g[r][f] == k { return (f, r) } }
        return nil
    }

    /// Is square (f,r) attacked by any piece of color `byWhite`?
    private static func attacked(_ g: [[Character?]], _ f: Int, _ r: Int, byWhite: Bool) -> Bool {
        func at(_ ff: Int, _ rr: Int) -> Character? {
            (0..<8).contains(ff) && (0..<8).contains(rr) ? g[rr][ff] : nil
        }
        func isEnemy(_ c: Character?, _ upper: Character) -> Bool {
            guard let c else { return false }
            return c.isUppercase == byWhite && Character(c.uppercased()) == upper
        }
        // pawns: a white pawn attacks up-diagonals (so it sits one rank BELOW the target)
        let pr = byWhite ? r - 1 : r + 1
        if isEnemy(at(f - 1, pr), "P") || isEnemy(at(f + 1, pr), "P") { return true }
        // knights
        for (df, dr) in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)]
            where isEnemy(at(f + df, r + dr), "N") { return true }
        // king
        for df in -1...1 { for dr in -1...1 where (df, dr) != (0, 0)
            && isEnemy(at(f + df, r + dr), "K") { return true } }
        // sliding: diagonals (B/Q) and orthogonals (R/Q)
        let rays: [((Int, Int), Character)] = [
            ((1,1),"B"),((1,-1),"B"),((-1,1),"B"),((-1,-1),"B"),
            ((1,0),"R"),((-1,0),"R"),((0,1),"R"),((0,-1),"R")]
        for ((df, dr), kind) in rays {
            var ff = f + df, rr = r + dr
            while (0..<8).contains(ff) && (0..<8).contains(rr) {
                if let c = g[rr][ff] {                       // hit a piece → blocks the ray
                    if c.isUppercase == byWhite {
                        let u = Character(c.uppercased())
                        if u == kind || u == "Q" { return true }
                    }
                    break
                }
                ff += df; rr += dr                           // empty → keep sliding
            }
        }
        return false
    }

    private static func serialize(_ grid: [[Character?]]) -> String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = "", empty = 0
            for file in 0..<8 {
                if let p = grid[rank][file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(p)
                } else { empty += 1 }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        return rows.joined(separator: "/")
    }
}
