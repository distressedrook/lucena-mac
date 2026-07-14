import Foundation

// Runnable, dependency-free tests for ChessMove.isLegal (front-end move legality). No XCTest target
// exists, and ChessMove is pure Foundation, so this compiles directly against it:
//
//   swiftc app/Lucena/Support/ChessMove.swift app/Tests/ChessMoveLegalityTests.swift -o /tmp/cmt \
//     && /tmp/cmt
//
// Exits non-zero on any failure.

@main
struct ChessMoveLegalityTests {
    static var failures = 0

    static func check(_ fen: String, _ from: String, _ to: String, _ expect: Bool, _ name: String) {
        let got = ChessMove.isLegal(fen, from: from, to: to)
        if got != expect {
            failures += 1
            print("FAIL: \(name) — \(from)\(to) expected \(expect), got \(got)\n      \(fen)")
        } else {
            print("ok:   \(name)")
        }
    }

    static func main() {
        let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

        // --- basic pawn / piece movement ---
        check(start, "e2", "e4", true,  "pawn double push")
        check(start, "e2", "e3", true,  "pawn single push")
        check(start, "e2", "e5", false, "pawn can't jump 3")
        check(start, "g1", "f3", true,  "knight develops")
        check(start, "g1", "e2", false, "knight onto own pawn")
        check(start, "f1", "c4", false, "bishop blocked by own pawn")
        check(start, "d1", "d4", false, "queen blocked by own pawn")
        check(start, "e1", "e2", false, "king onto own pawn")
        check(start, "e2", "d3", false, "pawn can't capture empty diagonal")
        check(start, "a1", "a1", false, "no null move")

        // wrong side to move
        check(start, "e7", "e5", false, "black can't move on white's turn")
        check("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1", "e7", "e5", true,
              "black pawn double push on black's turn")

        // --- sliding after the pawn moves ---
        let openE = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
        check(openE, "f1", "c4", true,  "bishop out after e4")
        check(openE, "f1", "b5", true,  "bishop long diagonal")
        check(openE, "d1", "h5", true,  "queen out on the diagonal")
        check(openE, "f1", "g2", false, "bishop onto own pawn")

        // --- captures ---
        let cap = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"
        check(cap, "e4", "d5", true,  "pawn captures pawn")
        check(cap, "e4", "e5", true,  "pawn pushes past")
        check(cap, "e4", "f5", false, "pawn can't capture empty")

        // --- en passant ---
        // white pawn e5, black just played d7-d5 → exd6 e.p. is legal (ep target d6)
        let ep = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"
        check(ep, "e5", "d6", true,  "en passant capture")
        check(ep, "e5", "f6", false, "no en passant on the wrong file")
        // same position but no ep target available → the diagonal is illegal
        let noEp = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3"
        check(noEp, "e5", "d6", false, "no en passant without the target")

        // --- king safety: pins and getting out of check ---
        // white king e1, white bishop e2 pinned by black rook e8 → bishop can't leave the file
        let pin = "4r3/8/8/8/8/8/4B3/4K3 w - - 0 1"
        check(pin, "e2", "d3", false, "pinned bishop can't move off the pin")
        check(pin, "e1", "d1", true,  "king steps off the file")
        check(pin, "e1", "e2", false, "king can't step onto its own bishop")
        // white king in check from the rook must respond; a random pawn move is illegal
        let inCheck = "4r3/8/8/8/8/8/P7/4K3 w - - 0 1"
        check(inCheck, "a2", "a3", false, "can't ignore check")
        check(inCheck, "e1", "d1", true,  "king escapes check sideways")
        check(inCheck, "e1", "f2", true,  "king escapes off the file")

        // --- castling ---
        // clear back rank, all rights
        let cast = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        check(cast, "e1", "g1", true,  "white O-O")
        check(cast, "e1", "c1", true,  "white O-O-O")
        // rook gone / no right on that side
        let noRight = "r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1"
        check(noRight, "e1", "g1", false, "no O-O without the K right")
        check(noRight, "e1", "c1", true,  "O-O-O still legal")
        // castling through check: black rook on f8 attacks f1 → can't O-O
        let through = "r4rk1/8/8/8/8/8/8/R3K2R w KQ - 0 1"
        check(through, "e1", "g1", false, "can't castle through check (f1 attacked)")
        // castling with a blocker
        let blocked = "r3k2r/8/8/8/8/8/8/R2NK2R w KQkq - 0 1"
        check(blocked, "e1", "c1", false, "can't O-O-O through a blocker")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
