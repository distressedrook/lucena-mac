import Foundation

// Pure-data mirrors of the MCP server's live UI state (LLD-app §2.1). Decoded from the `/state`
// SSE event payloads with `.convertFromSnakeCase`, so properties are camelCase while the wire is
// snake_case. No presentation here — colors/glyphs/formatting live in the views' `...Style` enums.
// Defensive decoders tolerate missing keys so schema drift degrades gracefully.

// MARK: - board

struct BoardState: Codable, Equatable {
    var seq: Int
    var fen: String
    var arrows: [Arrow]
    var highlights: [Highlight]
    var caption: String?
    var eval: EvalBlock?
    var terminal: String?    // "checkmate" | "stalemate" | nil — the game is over, no move to make
    var hasPoisonedLine: Bool      // this position holds a trap for the player — clears on the next paint
    var poisonedLine: [PoisonedMove]?   // the FULL trap line from this position — held for on-reveal display

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        fen = try c.decode(String.self, forKey: .fen)
        arrows = try c.decodeIfPresent([Arrow].self, forKey: .arrows) ?? []
        highlights = try c.decodeIfPresent([Highlight].self, forKey: .highlights) ?? []
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        eval = try c.decodeIfPresent(EvalBlock.self, forKey: .eval)
        terminal = try c.decodeIfPresent(String.self, forKey: .terminal)
        hasPoisonedLine = try c.decodeIfPresent(Bool.self, forKey: .hasPoisonedLine) ?? false
        poisonedLine = try c.decodeIfPresent([PoisonedMove].self, forKey: .poisonedLine)
    }
    enum CodingKeys: String, CodingKey {
        case seq, fen, arrows, highlights, caption, eval, terminal, hasPoisonedLine, poisonedLine
    }

    /// The standard opening — the honest "no game loaded yet" board, shown before the coach sets one.
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// One move of the loaded poisoned line — `fen` is the position AFTER the move (VarNode shape),
    /// so the app can build it straight into a variation off the current board when it's revealed.
    struct PoisonedMove: Codable, Equatable {
        var uci: String
        var san: String
        var fen: String
    }

    /// "w" or "b" — the side to move, read from the FEN (grounds the turn label + eval orientation).
    var sideToMove: String { fen.split(separator: " ").dropFirst().first.map(String.init) ?? "w" }
}

// MARK: - move history (the navigator)

/// One ply of the game/drill line — `fen` is the position AFTER the move. Ply 0 is the start
/// (no san/uci). The move navigator renders and steps through these.
struct Ply: Decodable, Identifiable, Equatable {
    var n: Int
    var san: String?
    var uci: String?
    var fen: String
    var id: Int { n }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        san = try c.decodeIfPresent(String.self, forKey: .san)
        uci = try c.decodeIfPresent(String.self, forKey: .uci)
        fen = try c.decodeIfPresent(String.self, forKey: .fen) ?? BoardState.startFEN
    }
    enum CodingKeys: String, CodingKey { case n, san, uci, fen }

    /// Build a ply locally — for the client-driven drill line (playing the opponent's reply without a
    /// server round-trip). The custom decoder above suppresses the memberwise init, so declare it.
    init(n: Int, san: String?, uci: String?, fen: String) {
        self.n = n; self.san = san; self.uci = uci; self.fen = fen
    }
}

struct MoveHistory: Decodable {
    var seq: Int
    var plies: [Ply]

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        plies = try c.decodeIfPresent([Ply].self, forKey: .plies) ?? []
    }
    enum CodingKeys: String, CodingKey { case seq, plies }
}

// MARK: - live engine analysis

/// One engine line (a MultiPV slot): white-relative eval + the principal variation in SAN.
struct EngineLine: Decodable, Identifiable {
    var rank: Int
    var evalWhiteCp: Int
    var winPct: Double
    var pvSan: [String]
    var id: Int { rank }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        evalWhiteCp = try c.decodeIfPresent(Int.self, forKey: .evalWhiteCp) ?? 0
        winPct = try c.decodeIfPresent(Double.self, forKey: .winPct) ?? 50
        pvSan = try c.decodeIfPresent([String].self, forKey: .pvSan) ?? []
    }
    enum CodingKeys: String, CodingKey { case rank, evalWhiteCp, winPct, pvSan }
}

/// A live analysis snapshot for `fen` at `depth` — the top lines + the opening name (if known).
struct EngineLines: Decodable, Equatable {
    var fen: String
    var depth: Int
    var engine: String
    var opening: String?
    var lines: [EngineLine]

    static func == (a: EngineLines, b: EngineLines) -> Bool {
        a.fen == b.fen && a.depth == b.depth && a.lines.map(\.pvSan) == b.lines.map(\.pvSan)
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        fen = try c.decodeIfPresent(String.self, forKey: .fen) ?? ""
        depth = try c.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        engine = try c.decodeIfPresent(String.self, forKey: .engine) ?? ""
        opening = try c.decodeIfPresent(String.self, forKey: .opening)
        lines = try c.decodeIfPresent([EngineLine].self, forKey: .lines) ?? []
    }
    enum CodingKeys: String, CodingKey { case fen, depth, engine, opening, lines }
}

/// The `/move` reply — whether the pushed move was adjudicated (a drill) and, if so, was correct.
/// Drives the wrong-move hold: a drill move that isn't correct stays on the board until Retry.
struct MoveResult: Decodable {
    var ok: Bool
    var drill: Bool
    var correct: Bool?
    var finished: Bool?
    // A drill branch is solved but the opponent has other defences — HELD behind a Continue button.
    // The board stays on the solution; clicking Continue walks the next branch (server-side backtrack).
    var awaitContinue: Bool?

    init(ok: Bool = false, drill: Bool = false, correct: Bool? = nil, finished: Bool? = nil,
         awaitContinue: Bool? = nil) {
        self.ok = ok; self.drill = drill; self.correct = correct; self.finished = finished
        self.awaitContinue = awaitContinue
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        drill = try c.decodeIfPresent(Bool.self, forKey: .drill) ?? false
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct)
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished)
        awaitContinue = try c.decodeIfPresent(Bool.self, forKey: .awaitContinue)
    }
    enum CodingKeys: String, CodingKey { case ok, drill, correct, finished, awaitContinue }
}

struct Arrow: Codable, Equatable, Identifiable {
    var from: String
    var to: String
    var style: String?
    var factId: String?
    var id: String { "\(from)-\(to)-\(factId ?? "")" }
}

struct Highlight: Codable, Equatable, Identifiable {
    var square: String
    var style: String?
    var factId: String?
    var id: String { "\(square)-\(factId ?? "")" }
}

struct EvalBlock: Codable, Equatable {
    var cp: Int?
    var winPct: Double?
    var glyph: String?
}

// MARK: - beats

struct Beat: Codable, Equatable, Identifiable {
    var i: Int
    var kind: String          // "say" | "ask"
    var tone: String?         // on a say: teach | praise | correct | verdict
    var stops: Bool           // an ask stops the turn
    var segments: [Segment]
    var hints: [String]?
    var you: String?          // an inline player reply shown after this beat (mockup fidelity)
    var correct: Bool?        // on a "you" DRILL move: true → green check badge, false → red cross
    var move: String?         // on a "you" move: the SAN, rendered as a clickable navigator-style chip
    var fen: String?          // the position right after `move` — clicking the chip snaps the board here
    // "1.e4" — a FREEFORM move, to be rendered as a neutral move-list line rather than a "you" bubble.
    // Freeform is a shared analysis board driven from both sides, so there is no "you" to attribute the
    // move to. Absent → the beat is a real player utterance (typed text, or a drill move) and keeps the
    // bubble. It rides on kind:"you" so an older client just ignores the key and renders as before.
    var notation: String?
    var boardSeq: Int?
    var ts: Double?
    // On a kind:"card" beat — a saved ACTIVITY (a puzzle) the player attempted. The card sits in the
    // base conversation; tapping it reopens that activity (its own board/beats/variations). `activityIdx`
    // is which activity to reopen, `title` labels it, `status` is "attempted" | "solved".
    var activityIdx: Int?
    var title: String?
    var status: String?
    var activityKind: String?     // the reopened activity's kind ("puzzle", …)
    // The nonce the client stamped on a typed turn. A "you" beat is rendered LOCALLY the instant the
    // player sends (optimistic), then the server persists+echoes the same beat carrying this id back;
    // the client matches on it to reconcile the two into one (see StateStream.applyBeats) instead of
    // showing the message twice. nil on every server-authored beat.
    var clientId: String?
    var id: Int { i }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        i = try c.decodeIfPresent(Int.self, forKey: .i) ?? 0
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "say"
        tone = try c.decodeIfPresent(String.self, forKey: .tone)
        stops = try c.decodeIfPresent(Bool.self, forKey: .stops) ?? false
        segments = try c.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        hints = try c.decodeIfPresent([String].self, forKey: .hints)
        you = try c.decodeIfPresent(String.self, forKey: .you)
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct)
        move = try c.decodeIfPresent(String.self, forKey: .move)
        fen = try c.decodeIfPresent(String.self, forKey: .fen)
        notation = try c.decodeIfPresent(String.self, forKey: .notation)
        boardSeq = try c.decodeIfPresent(Int.self, forKey: .boardSeq)
        ts = try c.decodeIfPresent(Double.self, forKey: .ts)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        activityIdx = try c.decodeIfPresent(Int.self, forKey: .activityIdx)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        activityKind = try c.decodeIfPresent(String.self, forKey: .activityKind)
    }
    enum CodingKeys: String, CodingKey {
        // The stream decoder uses .convertFromSnakeCase, so incoming `client_id` arrives as `clientId`
        // (like `board_seq` → `boardSeq`) — the case must use the DEFAULT raw value, not "client_id",
        // or it never matches and reconciliation silently fails (the message doubles).
        case i, kind, tone, stops, segments, hints, you, correct, move, fen, notation, boardSeq, ts
        case clientId, activityIdx, title, status, activityKind
    }

    var isAsk: Bool { kind == "ask" }
    var isYou: Bool { kind == "you" }   // a player-turn beat — rendered as a right-aligned bubble
    var isOpp: Bool { kind == "opp" }   // Lucena playing the opponent's reply — a move chip, no tick
    var isCard: Bool { kind == "card" }  // a saved-activity card — tap to reopen the puzzle
    /// A move played on the shared analysis board: neither the coach's voice nor the player's, so it
    /// gets its own neutral lane. Needs `fen` too — the lane is a navigable chip, and without a
    /// position to snap to there is nothing to render.
    var isNeutralMove: Bool { isYou && notation != nil && fen != nil }
    var text: String { segments.map(\.text).joined() }

    /// In-app synthetic beat (previews / local feedback), not decoded from the stream.
    init(i: Int, kind: String, tone: String? = nil, stops: Bool = false,
         segments: [Segment], hints: [String]? = nil, you: String? = nil, ts: Double? = nil) {
        self.i = i; self.kind = kind; self.tone = tone; self.stops = stops
        self.segments = segments; self.hints = hints; self.you = you
        self.boardSeq = nil; self.ts = ts
    }

    /// Convenience: a single-text local beat with a timestamp (for the drill's feedback beats).
    init(i: Int, kind: String, tone: String? = nil, text: String, ts: Double? = nil) {
        self.init(i: i, kind: kind, tone: tone, segments: [Segment(text: text, tone: nil)], ts: ts)
    }
}

struct Segment: Codable, Equatable {
    var text: String
    var tone: String?          // nil (ink) | "em" (blue italic) | "mark" (red bold)
}

// MARK: - analysis (the push_analysis panel)

struct PositionAnalysis: Codable, Equatable {
    var seq: Int
    var fen: String
    var verdict: String
    var observations: [String]

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        fen = try c.decodeIfPresent(String.self, forKey: .fen) ?? ""
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict) ?? ""
        observations = try c.decodeIfPresent([String].self, forKey: .observations) ?? []
    }
    enum CodingKeys: String, CodingKey { case seq, fen, verdict, observations }
}

// MARK: - turn (the explicit accept/reject signal — LLD-app §2.3)

struct TurnState: Codable, Equatable {
    var state: String          // coachThinking | awaitingPlayer | awaitingProbe
    var verdict: MoveVerdict?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "awaiting_player"
        verdict = try c.decodeIfPresent(MoveVerdict.self, forKey: .verdict)
    }
    enum CodingKeys: String, CodingKey { case state, verdict }
}

struct MoveVerdict: Codable, Equatable {
    var move: String
    var result: String         // accepted | wrong
    var snapBack: Bool
}
