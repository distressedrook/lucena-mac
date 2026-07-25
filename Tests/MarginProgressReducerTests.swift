import Foundation

// Dependency-free tests for the margin loading stream's decision logic
// (repo pattern — no XCTest target; see ChessMoveLegalityTests):
//
//   swiftc Lucena/Support/MarginProgressReducer.swift \
//     Tests/MarginProgressReducerTests.swift -o /tmp/mprt && /tmp/mprt
//
// Exits non-zero on any failure.

@main
struct MarginProgressReducerTests {
    static var failures = 0
    typealias R = MarginProgressReducer

    static func check(_ got: R.Effect, _ expect: R.Effect, _ name: String) {
        if got != expect { failures += 1; print("FAIL: \(name) — got \(got), expected \(expect)") }
    }

    static func main() {
        var st = R.State()

        // fresh stream begins on i == 0
        check(R.reduce(&st, .init(fen: "A", stage: "pawns", i: 0)), .begin, "i0 begins")
        check(R.reduce(&st, .init(fen: "A", stage: "kings", i: 1)), .append, "same-fen appends")

        // stale mid-stream stage from an older fen is dropped
        check(R.reduce(&st, .init(fen: "OLD", stage: "kings", i: 2)), .ignore, "stale stage ignored")

        // delayed done from an older fen must NOT end the current cycle
        check(R.reduce(&st, .init(fen: "OLD", stage: "done", i: nil)), .ignore, "stale done ignored")
        if st.rollDone { failures += 1; print("FAIL: stale done set rollDone") }

        // the active fen's done finishes
        check(R.reduce(&st, .init(fen: "A", stage: "done", i: nil)), .finish, "active done finishes")
        if !st.rollDone { failures += 1; print("FAIL: active done did not set rollDone") }

        // a late same-fen stage after done is terminal-ignored (no clock restart)
        check(R.reduce(&st, .init(fen: "A", stage: "kings", i: 3)), .ignore, "post-done stage ignored")
        if !st.rollDone { failures += 1; print("FAIL: post-done stage cleared rollDone") }

        // a NEW position's stream restarts cleanly after done
        check(R.reduce(&st, .init(fen: "B", stage: "pawns", i: 0)), .begin, "new fen restarts")
        if st.rollDone || st.fens != ["B"] { failures += 1; print("FAIL: restart state wrong") }

        // done on an empty/cleared state (post reset/stop) is ignored
        var cleared = R.State()
        check(R.reduce(&cleared, .init(fen: "B", stage: "done", i: nil)), .ignore, "done after clear ignored")

        // a malformed event with a MISSING index must not reset an active stream
        var active = R.State(fens: ["A"], rollDone: false)
        check(R.reduce(&active, .init(fen: "B", stage: "pawns", i: nil)), .ignore, "nil index ignored")
        if active.fens != ["A"] { failures += 1; print("FAIL: nil-index event reset the stream") }

        // out-of-order first event (i != 0 with no active stream) is ignored
        var empty = R.State()
        check(R.reduce(&empty, .init(fen: "C", stage: "kings", i: 3)), .ignore, "orphan stage ignored")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("MarginProgressReducerTests: all passed")
    }
}
