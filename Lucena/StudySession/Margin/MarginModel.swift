import Foundation

/// Display model for the MARGIN — the right column of the v1 Annotated Board
/// (mac-client/V1_LAYOUT.md). Pure view-state: no networking, no derivation.
/// The margin reads the CURRENT position only (cursor-linked, never a
/// transcript); salience upstream decides which fields are populated, and the
/// view derives its visual state from what's present:
///
///   urgent      → the urgent card (full ink, one button)
///   rook/cards  → noted (one-liner + card stack, ≤1 expanded)
///   theory      → in-book (idea line + labeled doors)
///   epigraph    → move 1 (the book opens)
///   otherwise   → resting (always-true quiet reads; the margin is never empty)
struct MarginContent {
    var masthead: String?               // opening name — "SCANDINAVIAN DEFENSE"
    var epigraph: Epigraph?             // move 1 only
    var theory: TheoryCard?             // in book only
    var restingLines: [RestingLine]     // always available (phase, eval-in-words, structure)
    var rookLine: RookLine?             // noted: the coach's one-liner (≤2 lines, hard budget)
    var cards: [MarginCard]             // noted: collapsed headers; the view expands at most one
    var urgent: UrgentCard?             // urgent: tactic / drill offer / blunder
    var commandHints: [String]          // rotating placeholder for the command field
}

/// One quiet line of the resting state. `register` picks the ink voice:
/// chrome (mono, for "MIDDLEGAME · MOVE 14") vs prose (small serif, for
/// "Carlsbad structure · calm").
struct RestingLine: Identifiable {
    enum Register { case chrome, prose }
    let id = UUID()
    let text: String
    var register: Register = .prose
}

/// The move-1 epigraph — a fact-checked quote (lucena_core.content.epigraph,
/// seeded per game so a session keeps its quote like a book keeps its).
struct Epigraph {
    let quote: String
    let author: String
    var source: String?
}

/// The in-book theory card: the authored idea line plus the LABELED DOORS —
/// each plausible next move tagged with the variation it enters (fen→name
/// lookup) and how often players at this rating choose it (Maia).
struct TheoryCard {
    let idea: String?                   // authored annotation (112 openings) or carve-out line
    let doors: [TheoryDoor]
}

struct TheoryDoor: Identifiable {
    let id = UUID()
    let san: String
    var variation: String?              // nil = unnamed sideline (Maia % still shows)
    var typicalPct: Int?
}

/// The rook's marginalia line. Tone mirrors the beat schema (praise / teach /
/// correct) and keys the avatar's pose.
struct RookLine {
    enum Tone { case praise, teach, correct }
    let text: String
    var tone: Tone = .teach
}

/// A collapsed-by-default card. Sections render as headed groups of short
/// rows; rows may carry moves (Menlo inline) and square tags (tappable —
/// they'll draw arrows on the board once wired).
struct MarginCard: Identifiable {
    let id: String                      // stable across re-renders ("plan-white", "facts")
    let title: String                   // header label, rendered small-caps chrome
    var count: Int?                     // "POSITION FACTS (3)"
    var sections: [CardSection]
}

struct CardSection: Identifiable {
    let id = UUID()
    var heading: String?
    var rows: [CardRow]
}

struct CardRow: Identifiable {
    let id = UUID()
    let text: String
    var moves: [String] = []            // SAN, shown as Menlo chips after the text
    var squares: [String] = []          // square tags — the future arrow taps
}

/// The urgent notice: loudest thing in the column, still typographic — never
/// a modal, never covers the board (the drill-invitation ruling).
struct UrgentCard {
    let glyph: String                   // "⚔"
    let text: String
    let buttonTitle: String             // "Drill it"
}

// MARK: - Fixtures (previews / unwired build; APIs land later)

extension MarginContent {
    /// Move 1: the book opens — epigraph + the opening naming itself.
    static let sampleMove1 = MarginContent(
        masthead: "King's Pawn Game",
        epigraph: Epigraph(
            quote: "Every pawn is a potential queen.",
            author: "James Mason",
            source: "The Art of Chess, 1895"),
        theory: nil,
        restingLines: [],
        rookLine: nil, cards: [], urgent: nil,
        commandHints: ["give me a puzzle", "what are my stats?", "endgame lesson"])

    /// In book: the theory card with labeled doors.
    static let sampleTheory = MarginContent(
        masthead: "Scandinavian Defense",
        epigraph: nil,
        theory: TheoryCard(
            idea: "Black trades the center pawn at once for early queen activity — "
                + "the whole opening is a bet that the tempo lost to Nc3 is worth "
                + "the cleared center.",
            doors: [
                TheoryDoor(san: "Qa5", variation: "Classical Variation", typicalPct: 48),
                TheoryDoor(san: "Qd6", variation: "Modern Variation", typicalPct: 31),
                TheoryDoor(san: "Qd8", variation: "Valencian Variation", typicalPct: 9),
            ]),
        restingLines: [],
        rookLine: nil, cards: [], urgent: nil,
        commandHints: ["give me a puzzle", "show the plan"])

    /// Resting: nothing clears the bar — the always-true quiet reads.
    static let sampleResting = MarginContent(
        masthead: "Scandinavian Defense",
        epigraph: nil, theory: nil,
        restingLines: [
            RestingLine(text: "MIDDLEGAME · MOVE 14", register: .chrome),
            RestingLine(text: "Roughly equal · material even"),
            RestingLine(text: "Carlsbad structure · calm"),
        ],
        rookLine: nil, cards: [], urgent: nil,
        commandHints: ["give me a puzzle", "what are my stats?"])

    /// Noted: the book-exit moment — rook line + plan card + facts.
    static let sampleNoted = MarginContent(
        masthead: "Scandinavian Defense",
        epigraph: nil, theory: nil,
        restingLines: [
            RestingLine(text: "MIDDLEGAME · MOVE 12", register: .chrome),
            RestingLine(text: "Roughly equal · material even"),
        ],
        rookLine: RookLine(text: "Book ends here. This is the real game now.", tone: .teach),
        cards: [
            MarginCard(id: "plan-white", title: "Plan for White", sections: [
                CardSection(heading: "Minority attack", rows: [
                    CardRow(text: "Advance the queenside pawns", moves: ["b4", "b5"]),
                    CardRow(text: "The lever creates a lasting weakness",
                            squares: ["b5", "c6"]),
                ]),
                CardSection(heading: "Piece play", rows: [
                    CardRow(text: "The knight belongs on the outpost",
                            moves: ["Nd2", "Nb3", "Nc5"], squares: ["c5"]),
                ]),
            ]),
            MarginCard(id: "facts", title: "Position Facts", count: 3, sections: [
                CardSection(rows: [
                    CardRow(text: "The c8 bishop is entombed — its only route out",
                            squares: ["d7", "e8"]),
                    CardRow(text: "Black's c6 pawn is backward", squares: ["c6"]),
                    CardRow(text: "White's rooks are connected"),
                ]),
            ]),
        ],
        urgent: nil,
        commandHints: ["drill it", "show the plan"])

    /// Urgent: a forcing win exists — the drill invitation.
    static let sampleUrgent = MarginContent(
        masthead: "Scandinavian Defense",
        epigraph: nil, theory: nil,
        restingLines: [
            RestingLine(text: "MIDDLEGAME · MOVE 17", register: .chrome),
        ],
        rookLine: nil, cards: [],
        urgent: UrgentCard(glyph: "⚔",
                           text: "White has a forcing win in this position.",
                           buttonTitle: "Drill it"),
        commandHints: ["drill it"])
}
