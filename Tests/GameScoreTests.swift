import Foundation

// Runnable, dependency-free tests for the Analysis panel's game score (MoveListStyle.rows). The
// score is the one list that shows the mainline AND an open variation at once, so its grouping
// rules are worth pinning: SwiftUI is not needed for any of it.
//
//   swiftc Lucena/StudySession/VariationModel.swift Lucena/StudySession/GameScore.swift \
//     Tests/GameScoreTests.swift -o /tmp/gst && /tmp/gst
//
// Exits non-zero on any failure.

@main
struct GameScoreTests {
    static var failures = 0

    static func check(_ name: String, _ got: String, _ want: String) {
        if got != want {
            failures += 1
            print("FAIL: \(name)\n      want \(want)\n      got  \(got)")
        } else {
            print("ok:   \(name)")
        }
    }

    /// A row as the view lays it out: a mainline row is a numbered gutter plus two columns (an
    /// absent move leaves "…"); a variation row is an indented aside behind a rule, carrying its
    /// number inline and no empty columns.
    static func render(_ rows: [MoveRow]) -> String {
        rows.map { r -> String in
            let w = r.white.map { $0.move.san ?? "?" }
            let b = r.black.map { $0.move.san ?? "?" }
            if r.isVariation {
                var out = "  |"
                if let w { out += "\(r.number). \(w)" }
                if let b { out += w == nil ? "\(r.number)… \(b)" : " \(b)" }
                return out
            }
            return "\(r.number). \(w ?? "…")" + (b.map { " " + $0 } ?? "")
        }.joined(separator: " / ")
    }

    static func mainline(_ sans: [String], from: Int = 1) -> [LineMove] {
        // fens only need side-to-move and fullmove: that is all the score reads
        var out: [LineMove] = []
        var white = true, number = from
        for (i, san) in sans.enumerated() {
            let fen = "8/8/8/8/8/8/8/8 \(white ? "b" : "w") - - 0 \(white ? number : number + 1)"
            out.append(LineMove(id: "m\(i)", san: san, uci: "x", fen: fen,
                                isBranch: false, node: nil, mainPly: i))
            if !white { number += 1 }
            white.toggle()
        }
        return out
    }

    static func entry(_ m: LineMove, variation: Bool = false, current: Bool = false) -> ScoreMove {
        ScoreMove(id: m.id + (variation ? "v" : ""), move: m, isVariation: variation,
                  isCurrent: current, target: variation ? .line(0) : .mainline(0))
    }

    static func main() {
        // --- the owner's screenshot: 1.e4 e5 2.Nf3 Nc6 with 2… Nf6 as an aside ---
        let main = mainline(["e4", "e5", "Nf3", "Nc6"])
        var side = main[3]                                     // same number/colour as 2…Nc6
        side = LineMove(id: "v0", san: "Nf6", uci: "g8f6", fen: side.fen,
                        isBranch: true, node: nil, mainPly: nil)
        let score = main.prefix(4).map { entry($0) } + [entry(side, variation: true, current: true)]
        check("mainline stays whole, the sideline is an aside",
              render(MoveListStyle.rows(Array(score))),
              "1. e4 e5 / 2. Nf3 Nc6 /   |2… Nf6")

        // --- a sideline replacing a WHITE move: the game resumes on its own row ---
        let m2 = mainline(["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])
        let sideW = LineMove(id: "v1", san: "Bc4", uci: "f1c4", fen: m2[4].fen,
                             isBranch: true, node: nil, mainPly: nil)
        let score2 = m2.prefix(5).map { entry($0) } + [entry(sideW, variation: true)]
                     + [entry(m2[5])]
        check("the game picks back up after the aside",
              render(MoveListStyle.rows(score2)),
              "1. e4 e5 / 2. Nf3 Nc6 / 3. Bb5 /   |3. Bc4 / 3. … a6")

        // --- a sideline NEVER pairs onto a mainline row ---
        let paired = MoveListStyle.rows(Array(score))
        check("the sideline row is its own row", "\(paired.count)", "3")
        check("the mainline row 2 keeps its own black move",
              paired[1].black?.move.san ?? "nil", "Nc6")

        // --- the drill's "?" placeholder is not a move and never numbers itself ---
        let ph = LineMove(id: "solve-placeholder", san: "?", uci: nil,
                          fen: "8/8/8/8/8/8/8/8 w - - 0 3", isBranch: false, node: nil, mainPly: nil)
        check("the solve placeholder stays out of the score",
              render(MoveListStyle.rows(main.map { entry($0) } + [entry(ph)])),
              "1. e4 e5 / 2. Nf3 Nc6")

        // --- a black-to-move start reads "1… " (no white cell invented) ---
        let blackFirst = [LineMove(id: "b0", san: "c5", uci: "c7c5",
                                   fen: "8/8/8/8/8/8/8/8 w - - 0 2", isBranch: false,
                                   node: nil, mainPly: 0)]
        check("a black-to-move start opens with an empty white cell",
              render(MoveListStyle.rows(blackFirst.map { entry($0) })), "1. … c5")

        print(failures == 0 ? "\nall game-score tests passed" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
