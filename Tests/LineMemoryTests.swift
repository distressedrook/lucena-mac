import Foundation

// Runnable, dependency-free tests for the session's analysis memory (owner 2026-07-26: "can we also
// have front-end caching? while inside a session?"). Pure data, so it compiles on its own:
//
//   swiftc Lucena/Models/StateModels.swift Lucena/Support/LineMemory.swift \
//     Tests/LineMemoryTests.swift -o /tmp/lmt && /tmp/lmt
//
// Exits non-zero on any failure.

@main
struct LineMemoryTests {
    static var failures = 0

    static func check(_ name: String, _ got: String, _ want: String) {
        if got != want {
            failures += 1
            print("FAIL: \(name)\n      want \(want)\n      got  \(got)")
        } else {
            print("ok:   \(name)")
        }
    }

    static func lines(_ fen: String, depth: Int, cp: Int = 0) -> EngineLines {
        let json = """
        {"fen": "\(fen)", "depth": \(depth), "engine": "test", "lines":
         [{"rank": 1, "eval_white_cp": \(cp), "win_pct": 50, "pv_san": ["e4"]}]}
        """
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try! d.decode(EngineLines.self, from: Data(json.utf8))
    }

    static func main() {
        let A = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let sameBoardLater = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 9 40"
        let B = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

        var m = LineMemory()
        m.remember(lines(A, depth: 20, cp: 25))
        check("a remembered position answers", "\(m.lines(for: A)?.depth ?? -1)", "20")
        check("...and the clocks are not part of it",
              "\(m.lines(for: sameBoardLater)?.lines.first?.evalWhiteCp ?? -1)", "25")
        check("an unseen position is a miss", m.lines(for: B) == nil ? "nil" : "hit", "nil")

        // DEEPEST WINS: the server republishes its own cache at a shallower depth than we may
        // already hold, and a restarted search always comes back at depth 1 first.
        m.remember(lines(A, depth: 8, cp: 999))
        check("a shallower frame does not overwrite", "\(m.lines(for: A)?.depth ?? -1)", "20")
        m.remember(lines(A, depth: 24, cp: 30))
        check("a deeper one does", "\(m.lines(for: A)?.depth ?? -1)", "24")

        // Bounded: a long game visits a lot of positions.
        var small = LineMemory(max: 2)
        for i in 0..<3 { small.remember(lines("p\(i)/8/8/8/8/8/8/8 w - - 0 1", depth: 10)) }
        check("the memory is bounded", "\(small.count)", "2")
        check("the oldest went first",
              small.lines(for: "p0/8/8/8/8/8/8/8 w - - 0 1") == nil ? "gone" : "kept", "gone")

        m.forgetAll()
        check("a new chat remembers nothing", "\(m.count)", "0")

        print(failures == 0 ? "\nall line-memory tests passed" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
