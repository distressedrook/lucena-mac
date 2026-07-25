import Foundation

// Runnable, dependency-free parity tests for ChessMove.apply — the optimistic display FEN must
// match the server's board truth FIELD FOR FIELD. Every expectation below was generated from
// `lucena_core.board.Board(fen).apply(uci).fen` (the backend's own applier, used by
// ToolContext.play_move), not hand-written: the client FEN is compared against that echo to hold
// the loading highlights, and it keys the opening-book/theory lookup, so an approximated castling
// field / ep target / halfmove clock silently drops a position out of book.
//
//   swiftc Lucena/Support/ChessMove.swift Tests/ChessMoveApplyTests.swift -o /tmp/cma && /tmp/cma
//
// Exits non-zero on any failure. (No XCTest target exists; ChessMove is pure Foundation.)

@main
struct ChessMoveApplyTests {
    static var failures = 0

    static func check(_ name: String, _ fen: String, _ from: String, _ to: String,
                      _ promotion: Character?, _ expect: String) {
        guard let got = ChessMove.apply(fen, from: from, to: to, promotion: promotion) else {
            failures += 1
            print("FAIL: \(name) — apply returned nil\n      \(fen)")
            return
        }
        if got.fen != expect {
            failures += 1
            print("FAIL: \(name)\n      want \(expect)\n      got  \(got.fen)")
        } else {
            print("ok:   \(name)")
        }
    }

    static func main() {
        check("start double push emits the ep square",
              "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e2", "e4", nil,
              "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        check("quiet move ticks the halfmove clock",
              "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "g8", "f6", nil,
              "rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2")
        check("black double push ticks the fullmove number",
              "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "c7", "c5", nil,
              "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2")
        check("capture resets the halfmove clock",
              "rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3", "f3", "e5", nil,
              "rnbqkb1r/pppp1ppp/5n2/4N3/4P3/8/PPPP1PPP/RNBQKB1R b KQkq - 0 3")
        check("a king move drops both of its rights",
              "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "e1", "e2", nil,
              "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPPKPPP/RNBQ1BNR b kq - 1 2")
        check("kingside castling",
              "rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", "e1", "g1", nil,
              "rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 5 4")
        check("queenside castling",
              "r3kbnr/pppqpppp/2np4/8/3PP1b1/2N2N2/PPPQ1PPP/R3KB1R w KQkq - 6 6", "e1", "c1", nil,
              "r3kbnr/pppqpppp/2np4/8/3PP1b1/2N2N2/PPPQ1PPP/2KR1B1R b kq - 7 6")
        check("a rook leaving h1 drops K only",
              "rnbqkbnr/pppppppp/8/8/8/7P/PPPPPPP1/RNBQKBNR w KQkq - 0 2", "h1", "h2", nil,
              "rnbqkbnr/pppppppp/8/8/8/7P/PPPPPPPR/RNBQKBN1 b Qkq - 1 2")
        check("a rook leaving a1 drops Q only",
              "rnbqkbnr/1ppppppp/p7/8/P7/8/1PPPPPPP/RNBQKBNR w KQkq - 0 2", "a1", "a3", nil,
              "rnbqkbnr/1ppppppp/p7/8/P7/R7/1PPPPPPP/1NBQKBNR b Kkq - 1 2")
        check("capturing the rook ON h8 drops the enemy k",
              "rnbqkbnr/ppppppp1/8/7Q/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 3", "h5", "h8", nil,
              "rnbqkbnQ/ppppppp1/8/8/8/8/PPPPPPPP/RNB1KBNR b KQq - 0 3")
        check("en passant capture (clock resets, ep clears)",
              "rnbqkbnr/pp1ppppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 3", "d4", "e3", nil,
              "rnbqkbnr/pp1ppppp/8/8/8/4p3/PPPP1PPP/RNBQKBNR w KQkq - 0 4")
        check("promotion to queen",
              "8/P3k3/8/8/8/8/4K3/8 w - - 0 40", "a7", "a8", "Q",
              "Q7/4k3/8/8/8/8/4K3/8 b - - 0 40")

        print(failures == 0 ? "\nall apply-parity tests passed" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
