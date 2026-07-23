import Foundation

/// Display model for the MARGIN — the right column of the v1 Annotated Board
/// (mac-client/V1_LAYOUT.md). Pure view-state: no networking, no derivation.
/// The margin reads the CURRENT position only (cursor-linked, never a
/// transcript); salience upstream decides which fields are populated, and the
/// view derives its visual state from what's present:
///
///   epigraph → move 1 (the book opens) · theory → in book · cards →
///   everything after (the quiet position is itself a POSITION card — owner
///   ruling: "there is no rest; either move 1, book, or card"). When a
///   tactic fires, the urgent notice REPLACES everything — a forced win is
///   the position; the margin centers on it alone.
struct MarginContent {
    var masthead: String?               // opening name — "SCANDINAVIAN DEFENSE"
    var statusLine: String?             // chrome under the masthead — "MIDDLEGAME · MOVE 14"
    var epigraph: Epigraph?             // move 1 only
    var theory: TheoryCard?             // in book only
    var rookLine: RookLine?             // the coach's one-liner (≤2 lines, hard budget)
    var cards: [MarginCard]             // the card stack; the view expands at most one
    var urgent: UrgentCard?             // compact red notice above the cards
    var commandHints: [String]          // rotating placeholder for the command field
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

/// The urgent moment, set the way chess print has always set it: a STUDY
/// CAPTION. The Informant mark ("+−" = White is winning, "−+" = Black) in
/// red ink over the canonical caption ("White to play and win."), no box,
/// no wash — the composition and the whitespace do the work. When a forced
/// win exists nothing else matters (owner ruling): this replaces the margin
/// body. Never a modal, never covers the board.
struct UrgentCard {
    var mark: String = "+\u{2212}"      // Informant evaluation symbol
    let text: String                    // the caption — "White to play and win."
    let buttonTitle: String             // "Drill it"
}

// MARK: - Fixtures (previews / unwired build; APIs land later)

extension MarginContent {
    /// Move 1: the book opens — epigraph + the opening naming itself.
    static let sampleMove1 = MarginContent(
        masthead: "King's Pawn Game",
        statusLine: nil,
        epigraph: Epigraph(
            quote: "Every pawn is a potential queen.",
            author: "James Mason",
            source: "The Art of Chess, 1895"),
        theory: nil,
        rookLine: nil, cards: [], urgent: nil,
        commandHints: ["give me a puzzle", "what are my stats?", "endgame lesson"])

    /// In book: the theory card with labeled doors.
    static let sampleTheory = MarginContent(
        masthead: "Scandinavian Defense",
        statusLine: "OPENING · MOVE 3",
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
        rookLine: nil, cards: [], urgent: nil,
        commandHints: ["give me a puzzle", "show the plan"])

    /// Quiet: nothing salient — the position's state IS the card.
    static let sampleQuiet = MarginContent(
        masthead: "Scandinavian Defense",
        statusLine: "MIDDLEGAME · MOVE 14",
        epigraph: nil, theory: nil,
        rookLine: nil,
        cards: [
            MarginCard(id: "position", title: "Position", sections: [
                CardSection(rows: [
                    CardRow(text: "Roughly equal · material even"),
                    CardRow(text: "Carlsbad structure · calm"),
                    CardRow(text: "Kings castled short on both sides"),
                ]),
            ]),
        ],
        urgent: nil,
        commandHints: ["give me a puzzle", "what are my stats?"])

    /// Noted: the book-exit moment — rook line + plan card + facts.
    static let sampleNoted = MarginContent(
        masthead: "Scandinavian Defense",
        statusLine: "MIDDLEGAME · MOVE 12",
        epigraph: nil, theory: nil,
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
        statusLine: "MIDDLEGAME · MOVE 17",
        epigraph: nil, theory: nil,
        rookLine: nil,
        cards: [],                       // nothing else matters
        urgent: UrgentCard(text: "White to play and win.",
                           buttonTitle: "Drill it"),
        commandHints: ["drill it"])
}
