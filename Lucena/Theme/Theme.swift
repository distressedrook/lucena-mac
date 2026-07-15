import SwiftUI

/// The single source of visual truth — the "Annotated Board" print identity (paper & ink,
/// serif = the coach's voice, mono = moves & chrome, blue/red/gold accents, hard edges).
/// Views reference these tokens only; no hex, `Font.system`, point sizes, or raw SF Symbol
/// strings live in a view body. Add a token here rather than hardcoding.
enum Theme {

    // MARK: Palette — two inks on paper; one accent per element.
    enum Palette {
        static let paper = Color(hex: 0xF1EDE3)        // cards, light squares, terminal fg
        static let paperDeep = Color(hex: 0xECE8DE)    // rail, surfaces, you-bubbles
        static let desk = Color(hex: 0xE4E0D5)         // window bg (radial outer)
        static let backdrop = Color(hex: 0xDDD8CC)     // window backdrop

        static let ink = Color(hex: 0x1C1B18)          // text, borders, fills, dark pieces
        static let ink82 = ink.opacity(0.82)           // strong secondary
        static let ink70 = ink.opacity(0.70)           // secondary
        static let ink55 = ink.opacity(0.55)           // muted
        static let ink45 = ink.opacity(0.45)           // labels
        static let ink22 = ink.opacity(0.22)           // hairlines
        static let ink18 = ink.opacity(0.18)           // past-beat rule
        static let ink12 = ink.opacity(0.12)

        static let coachBlue = Color(hex: 0x1E4E7A)    // coach voice, ideas, active beat, "!"
        static let mistakeRed = Color(hex: 0xA62A21)   // threats, "?!"/"?"/"??", wrong
        static let correctGreen = Color(hex: 0x2E7D46) // solved / right move — the verdict check badge
        static let gold = Color(hex: 0xB8862F)         // active, accents, "▸", prompt

        static let boardLight = Color(hex: 0xF1EDE3)
        static let boardDark = Color(hex: 0xE6E1D3)    // + 45° ink hatch (drawn separately)
        static let boardHatch = ink.opacity(0.30)

        static let terminalBg = Color(hex: 0x14130F)   // near-black seal
        static let terminalFg = Color(hex: 0xF1EDE3)
        static let termDim = Color(white: 0.94).opacity(0.42)
        static let termBright = Color(white: 0.94).opacity(0.82)
        static let termGreen = Color(hex: 0x8FB79A)    // ok
        static let termAmber = Color(hex: 0xC99B4A)    // working
    }

    // MARK: Spacing — loose 2/4px steps, not a strict grid.
    enum Spacing {
        static let none: CGFloat = 0
        static let hair: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32     // board ↔ margin
        static let xxl: CGFloat = 36
        static let xxxl: CGFloat = 52   // page sections
    }

    // MARK: Typography — three voices. Serif speaks, mono annotates.
    enum Typography {
        static let display = Font.system(size: 30, weight: .semibold, design: .serif)
        static let heading = Font.system(size: 21, weight: .semibold, design: .serif)
        static let coachBody = Font.system(size: 17.5, weight: .regular, design: .serif)
        static let aside = Font.system(size: 14.5, weight: .regular, design: .serif).italic()
        static let youBubble = Font.system(size: 15, weight: .regular, design: .serif)
        static let mark = Font.system(size: 21, weight: .semibold, design: .serif) // ?! ! glyph

        // Menlo (not SF Mono): SF Mono lacks the black chess glyphs (♞♛♜…), so figurine notation fell
        // back to an inconsistent per-glyph font and rendered the knight/pawn wrong. Menlo carries the
        // full chess set, so all figurines render correctly and consistently. Still monospaced.
        static let move = Font.custom("Menlo", size: 14)
        static let moveLg = Font.custom("Menlo", size: 15)
        static let evalReadout = Font.system(size: 12.5, weight: .semibold, design: .monospaced)
        static let terminal = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let chatInput = Font.system(size: 12.5, weight: .regular, design: .monospaced)
        static let label = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let labelSmall = Font.system(size: 9.5, weight: .regular, design: .monospaced)
        static let coordinate = Font.system(size: 10.5, weight: .regular, design: .monospaced)
    }

    // MARK: Tracking — mono uppercase labels (points; the design's em values at their size).
    enum Tracking {
        static let label: CGFloat = 1.5     // ~.14em at 11px
        static let labelWide: CGFloat = 1.8 // ~.16em
        static let button: CGFloat = 0.7    // ~.06em
    }

    // MARK: Radius — print has no rounded corners; only circles (handled by Circle()).
    enum Radius {
        static let none: CGFloat = 0
    }

    // MARK: Size — named fixed dimensions.
    enum Size {
        // window
        static let windowDefault = CGSize(width: 1300, height: 900)   // fallback if no screen
        static let windowMin = CGSize(width: 1100, height: 770)
        // rail + board
        static let rail: CGFloat = 250
        static let boardDefault: CGFloat = 464       // previews / fixed contexts
        static let boardMin: CGFloat = 360
        static let boardMax: CGFloat = 860           // board fills the column up to this
        static let boardFramePad: CGFloat = 7
        static let boardReserve: CGFloat = 20        // frame + shadow room when height-fitting
        // panes
        static let evalBar = CGSize(width: 112, height: 10)
        static let terminalMin: CGFloat = 120        // min terminal-pane height (before it grows)
        static let terminalTitleBar: CGFloat = 30    // title-bar height (content→pane sizing)
        static let terminalFontSize: CGFloat = 12
        static let logo: CGFloat = 40
        static let coachAvatar: CGFloat = 26
        // content layout
        static let contentPadTop: CGFloat = 20
        static let contentPadH: CGFloat = 30
        static let contentPadBottom: CGFloat = 14
        static let bodyTopGap: CGFloat = 18
        static let settingsMenuTop: CGFloat = 52
        // move list
        static let moveNumberColumn: CGFloat = 34    // "12." gutter
        static let moveCell: CGFloat = 92            // a white/black move cell
    }

    // MARK: Symbol — named SF Symbols.
    enum Symbol {
        static let gear = "gearshape"
        static let send = "arrow.up"
        static let plus = "plus"
        static let retry = "arrow.uturn.backward"
        static let flip = "arrow.left.arrow.right"
        static let engine = "cpu"
        static let chevronDown = "chevron.down"
        static let chevronRight = "chevron.right"
        static let variationCaret = "arrowtriangle.up.fill"   // a move that hides variations
        static let branch = "arrow.turn.down.right"           // a variation's divergence point
        static let back = "chevron.left"                      // pop one variation level
        static let cancel = "xmark"                           // back to the mainline
    }

    // MARK: Glyph — text glyphs the print set uses.
    enum Glyph {
        static let prompt = "❯"
        static let play = "▸"
    }

    /// The window's paper radial — deck under the print.
    static let windowBackground = RadialGradient(
        colors: [Color(hex: 0xF3EFE6), Palette.paperDeep, Palette.desk],
        center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 900)
}

extension Color {
    /// 0xRRGGBB literal → Color. Confined to `Theme` (the only place hex is allowed).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
