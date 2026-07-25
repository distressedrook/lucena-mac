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
            // placements are unique per ply: the forest keys on the first FOUR fen fields, so
            // identical placements would collide (and, before the cycle guard, recurse forever)
            let fen = "p\(i)/8/8/8/8/8/8/8 \(white ? "b" : "w") - - 0 \(white ? number : number + 1)"
            out.append(LineMove(id: "m\(i)", san: san, uci: "x", fen: fen,
                                isBranch: false, node: nil, mainPly: i))
            if !white { number += 1 }
            white.toggle()
        }
        return out
    }

    static func entry(_ m: LineMove, variation: Bool = false, current: Bool = false,
                      depth: Int = 1, block: String = "v") -> ScoreMove {
        ScoreMove(id: m.id + (variation ? "v" : ""), move: m,
                  depth: variation ? depth : 0, blockId: variation ? block : "main",
                  isCurrent: current,
                  target: variation ? .variation(stack: [], cursor: 0) : .mainline(0))
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

        // --- two sidelines at the same move never share a row ---
        let alt1 = LineMove(id: "s1", san: "Nf6", uci: "g8f6", fen: main[3].fen,
                            isBranch: true, node: nil, mainPly: nil)
        let alt2 = LineMove(id: "s2", san: "d6", uci: "d7d6", fen: main[3].fen,
                            isBranch: true, node: nil, mainPly: nil)
        check("each sideline gets its own row",
              render(MoveListStyle.rows(main.map { entry($0) }
                                        + [entry(alt1, variation: true, block: "a"),
                                           entry(alt2, variation: true, block: "b")])),
              "1. e4 e5 / 2. Nf3 Nc6 /   |2… Nf6 /   |2… d6")

        // --- a subline indents again ---
        let sub = LineMove(id: "s3", san: "Bc4", uci: "f1c4",
                           fen: "8/8/8/8/8/8/8/8 b - - 0 3", isBranch: true, node: nil, mainPly: nil)
        let deep = MoveListStyle.rows(main.map { entry($0) }
                                      + [entry(alt1, variation: true, block: "a"),
                                         entry(sub, variation: true, depth: 2, block: "c")])
        check("the subline carries its own depth", "\(deep.last?.depth ?? -1)", "2")

        // --- a black-to-move start reads "1… " (no white cell invented) ---
        let blackFirst = [LineMove(id: "b0", san: "c5", uci: "c7c5",
                                   fen: "8/8/8/8/8/8/8/8 w - - 0 2", isBranch: false,
                                   node: nil, mainPly: 0)]
        check("a black-to-move start opens with an empty white cell",
              render(MoveListStyle.rows(blackFirst.map { entry($0) })), "1. … c5")

        // ================= the tree walk (MoveListStyle.score) =================
        // 1.e4 e5 2.Nf3 Nc6, a sideline 2… Nf6 off move 2, and a "what if" off the LIVE tip.
        let root = mainline(["e4", "e5", "Nf3", "Nc6"])
        var forest = VariationForest()
        // its own position — a sideline move never lands where the move it replaces did
        let nf6 = VarNode(uci: "g8f6", san: "Nf6", fen: "v0/8/8/8/8/8/8/8 w - - 0 3")
        _ = forest.add(nf6, from: root[2].fen)                 // replaces 2…Nc6
        let tip = VarNode(uci: "f1c4", san: "Bc4", fen: "v1/8/8/8/8/8/8/8 b - - 0 3")
        _ = forest.add(tip, from: root[3].fen)                 // a what-if from the live position

        let tree = MoveListStyle.score(mainline: root, variations: forest, shown: root,
                                       cursor: 3, inVariation: false, currentPly: 3)
        check("the tree shows without entering it",
              render(MoveListStyle.rows(tree)),
              "1. e4 e5 / 2. Nf3 Nc6 /   |2… Nf6 /   |3. Bc4")
        check("the live tip's own what-if is in the score",
              tree.contains { $0.move.san == "Bc4" } ? "yes" : "no", "yes")
        check("the mainline move under the cursor is the current one",
              tree.first { $0.isCurrent }?.move.san ?? "none", "Nc6")

        // Inside the sideline: the sideline move is current, and clicking it carries the stack.
        let shownVar = Array(root.prefix(3)) + [
            LineMove(id: nf6.id.uuidString, san: "Nf6", uci: "g8f6", fen: nf6.fen,
                     isBranch: true, node: nf6, mainPly: nil)]
        let inVar = MoveListStyle.score(mainline: root, variations: forest, shown: shownVar,
                                        cursor: 3, inVariation: true, currentPly: 3)
        check("inside the sideline, the sideline move is current",
              inVar.first { $0.isCurrent }?.move.san ?? "none", "Nf6")
        if case .variation(let stack, let cursor)? = inVar.first(where: { $0.move.san == "Nf6" })?.target {
            check("its target opens that exact line", "\(stack.first?.branchLineIndex ?? -1)/\(cursor)", "2/3")
        } else {
            failures += 1; print("FAIL: the sideline entry carries no variation target")
        }

        // Arrowed back onto the shared prefix WHILE in the variation: a mainline move is current —
        // the case where reading `inVariation` alone highlighted nothing at all.
        let onPrefix = MoveListStyle.score(mainline: root, variations: forest, shown: shownVar,
                                           cursor: 2, inVariation: true, currentPly: 3)
        check("the shared prefix still highlights, from inside a variation",
              onPrefix.first { $0.isCurrent }?.move.san ?? "none", "Nf3")
        check("...and exactly one move is current",
              "\(onPrefix.filter { $0.isCurrent }.count)", "1")

        // A REPETITION must not walk forever: a sideline that returns to the position it branched
        // from is one forest key pointing at itself.
        var loopy = VariationForest()
        let back = VarNode(uci: "g1f3", san: "Nf3", fen: root[2].fen)   // lands back on the branch fen
        _ = loopy.add(back, from: root[2].fen)
        let cyclic = MoveListStyle.score(mainline: root, variations: loopy, shown: root,
                                         cursor: 3, inVariation: false, currentPly: 3)
        check("a repetition terminates instead of recursing",
              "\(cyclic.filter { $0.isVariation }.count)", "1")

        print(failures == 0 ? "\nall game-score tests passed" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
