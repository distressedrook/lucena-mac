import Foundation

/// The margin loading stream's decision logic, extracted PURE so it is
/// testable with the repo's dependency-free swiftc pattern (no XCTest target;
/// see Tests/). StateStream owns the storage and the clock Task; this owns
/// every accept/ignore decision — fen correlation included (a delayed `done`
/// from an older position must never end the current cycle).
enum MarginProgressReducer {

    struct Ev: Equatable {
        var fen: String?
        var stage: String?
        var i: Int?
    }

    struct State: Equatable {
        var fens: [String?] = []      // one entry per accepted stage (first = active fen)
        var rollDone = false
    }

    enum Effect: Equatable {
        case ignore                   // stale event — no state change
        case begin                    // fresh stream: reset storage, start the clock
        case append                   // stage accepted for the active fen
        case finish                   // the ACTIVE fen's rolls are done: stop the clock
    }

    static func reduce(_ st: inout State, _ ev: Ev) -> Effect {
        if ev.stage == "done" {
            guard !st.fens.isEmpty, ev.fen == st.fens.first else { return .ignore }
            st.rollDone = true
            return .finish
        }
        if ev.i == 0 {                // explicit: a MISSING index must never
            st = State(fens: [ev.fen], rollDone: false)   // reset an active
            return .begin                                 // stream (Codex M)
        }
        if ev.i == nil { return .ignore }   // malformed non-done event
        // a FINISHED stream is terminal: a late same-fen stage must not
        // restart the clock or append post-completion data (Codex M, r6)
        guard !st.rollDone, !st.fens.isEmpty, ev.fen == st.fens.first
        else { return .ignore }
        st.fens.append(ev.fen)
        return .append
    }
}
