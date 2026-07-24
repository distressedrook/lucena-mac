import Foundation

/// Display model for the MARGIN — the v1 right column. The backend hands
/// over the deterministic sheet (assessment + per-side sections) plus its
/// pretty-printed JSON; the view renders three sections (owner 2026-07-23):
/// the assessment badges, WHITE, BLACK, and the raw JSON at the foot.
struct MarginContent: Decodable {
    var statusLine: String?             // "ROLLING…" · "PRE-VERIFY …" · "POST-VERIFY"
    var raw: String?                    // the JSON section (verbatim sheet)
    var sheet: Sheet?                   // the structured read (badges + sides)
    var plansPending: Bool = false      // the verify gate is still running — poll
    // AUTHORED content (2026-07-24, /content wired): human-written and
    // source-checked, not generated — the epigraph opens the game, the
    // theory card names the opening and leads with its annotation. Both
    // ride ALONGSIDE the sheet, never instead of it.
    var masthead: String?               // the opening's name, when in book
    var epigraph: Epigraph?             // move 1 only
    var theory: Theory?                 // in book only

    private enum CodingKeys: String, CodingKey {
        case statusLine, raw, sheet, plansPending, masthead, epigraph, theory
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusLine = try c.decodeIfPresent(String.self, forKey: .statusLine)
        raw = try c.decodeIfPresent(String.self, forKey: .raw)
        sheet = try c.decodeIfPresent(Sheet.self, forKey: .sheet)
        plansPending = try c.decodeIfPresent(Bool.self, forKey: .plansPending) ?? false
        masthead = try c.decodeIfPresent(String.self, forKey: .masthead)
        epigraph = try c.decodeIfPresent(Epigraph.self, forKey: .epigraph)
        theory = try c.decodeIfPresent(Theory.self, forKey: .theory)
    }

    init(statusLine: String? = nil, raw: String? = nil,
         sheet: Sheet? = nil, plansPending: Bool = false,
         masthead: String? = nil, epigraph: Epigraph? = nil,
         theory: Theory? = nil) {
        self.statusLine = statusLine
        self.raw = raw
        self.sheet = sheet
        self.plansPending = plansPending
        self.masthead = masthead
        self.epigraph = epigraph
        self.theory = theory
    }
}

// MARK: - authored content (/content, via lucena_core.content)

/// A fact-checked quote, seeded by SESSION so a game keeps its epigraph.
struct Epigraph: Decodable {
    let quote: String
    let author: String
    let source: String?
}

/// The in-book theory card: the authored annotation's lead sentences, plus
/// the labeled DOORS — where each named continuation goes.
struct Theory: Decodable {
    let idea: String?
    let doors: [Door]
    /// Set when `idea` is quoted from an external source (Wikibooks, CC
    /// BY-SA) rather than our own authored annotation — the license REQUIRES
    /// this credit + link be shown wherever the text appears.
    let attribution: Attribution?
}

/// Source credit for externally-licensed theory text (CC BY-SA).
struct Attribution: Decodable {
    let text: String
    let url: String
}

struct Door: Decodable, Identifiable {
    var id: String { san + variation }
    let san: String
    let variation: String
    let typicalPct: Double?

    private enum CodingKeys: String, CodingKey {
        case san, variation, typicalPct = "typicalPct"
    }
}

// MARK: - The sheet (lucena-plans/sheet@1, the fields the UI reads)

struct Sheet: Decodable {
    let assessment: Assessment
    let sides: Sides
    let activity: ActivityRead?
    /// Server-computed VERDICT chips — the categorical flags (weak colour
    /// complex) and the decisive verdict ("White is winning"). The magnitude
    /// metrics moved to `bars`.
    let badges: [String]?
    /// Labeled 0-1 bars driven by COMPARABLE quantities (owner 2026-07-24:
    /// "bars instead of labels"): Eval/Activity/Space centered at `mid` 0.5
    /// (White edge past the midline), king safety absolute (0=safe..1=lost,
    /// no mid). No control bar.
    let bars: [Bar]?
}

/// One labeled bar. `mid` (0.5) draws a contested midline for a centered,
/// White-minus-Black metric; absent for an absolute 0-1 metric.
struct Bar: Decodable, Identifiable {
    var id: String { label }
    let label: String
    let value: Double
    let mid: Double?
}

/// Whose pieces are the more active — a VERDICT, not a number (owner
/// 2026-07-24: "normalization isn't the way we show this; show it as a
/// badge"). `leader` is "White" | "Black" | nil, computed server-side; the
/// client never parses `standing` prose and never renders the raw 0-1,
/// which was false precision (0.681 vs 0.527 tells a reader nothing).
struct ActivityRead: Decodable {
    let leader: String?
    let standing: String?
}

struct Assessment: Decodable {
    let verdict: String                 // "The position is roughly equal."
    let character: PositionCharacter
    let gamePhase: Phase?
    let materialStability: MaterialStability?

    private enum CodingKeys: String, CodingKey {
        case verdict, character, gamePhase = "game_phase"
        case materialStability = "material_stability"
    }
}

/// Is the material edge bankable? `why` explains a soft one ("up a pawn
/// now, won't be soon" — a doubled pawn, a piece in tension, …).
struct MaterialStability: Decodable {
    let leader: String?
    let soft: Bool
    let why: [String]
}

struct PositionCharacter: Decodable {
    let bucket: String                  // DYNAMIC | QUIET | SHARP …
    let summary: String
}

struct Phase: Decodable { let name: String }

struct Sides: Decodable {
    let white: Side
    let black: Side
}

/// One color's scouting report — every field optional/defaulted so a thin
/// pre-verify sheet still decodes.
struct Side: Decodable {
    let activity: SideActivity?
    let control: [String: Double]?      // center / kingside / queenside share
    let space: [String: SpaceRegion]?
    let plans: [Plan]
    let advisory: [Plan]
    let weaknesses: [String]
    let breaks: [PawnBreak]
    let passers: [Passer]
    let trapped: [TrappedPiece]
    let outposts: [Hole]

    private enum CodingKeys: String, CodingKey {
        case activity, control, space, plans, advisory, weaknesses,
             breaks, passers, trapped, outposts
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = try c.decodeIfPresent(SideActivity.self, forKey: .activity)
        control = try c.decodeIfPresent([String: Double].self, forKey: .control)
        space = try c.decodeIfPresent([String: SpaceRegion].self, forKey: .space)
        plans = try c.decodeIfPresent([Plan].self, forKey: .plans) ?? []
        advisory = try c.decodeIfPresent([Plan].self, forKey: .advisory) ?? []
        weaknesses = try c.decodeIfPresent([String].self, forKey: .weaknesses) ?? []
        breaks = try c.decodeIfPresent([PawnBreak].self, forKey: .breaks) ?? []
        passers = try c.decodeIfPresent([Passer].self, forKey: .passers) ?? []
        trapped = try c.decodeIfPresent([TrappedPiece].self, forKey: .trapped) ?? []
        outposts = try c.decodeIfPresent([Hole].self, forKey: .outposts) ?? []
    }
}

struct SideActivity: Decodable {
    let score: Double?                  // 0-1; DATA ONLY — never displayed
    let worst: PieceOn?
}

struct PieceOn: Decodable { let piece: String; let square: String }

struct SpaceRegion: Decodable {
    let score: Double
    let raw: Int
    let exploitable: [String]
}

struct Plan: Decodable, Identifiable {
    var id: String { idea }
    let idea: String
    let verified: Bool?
    let timing: String?                 // "immediate" | "developing" | "long-term"
}

struct PawnBreak: Decodable, Identifiable {
    var id: String { pawn + push }
    let pawn: String
    let push: String
    let playable: Bool
    let targets: [String]
}

struct Passer: Decodable, Identifiable {
    var id: String { square }
    let square: String
    let score: Double
    let blockaded: Bool
    let pathClear: Bool

    private enum CodingKeys: String, CodingKey {
        case square, score, blockaded, pathClear = "path_clear"
    }
}

struct TrappedPiece: Decodable, Identifiable {
    var id: String { piece + square }
    let piece: String
    let square: String
    let state: String                   // "trapped" | "restricted"
}

struct Hole: Decodable, Identifiable {
    var id: String { square }
    let square: String
    let outpost: Bool
}
