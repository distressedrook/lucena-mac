import SwiftUI

/// The Annotated Board — a printed-diagram rendition of a FEN plus the coach's grounded overlays
/// (arrows, highlights). Squares + hatch + highlights + arrows draw in one `Canvas`; pieces and
/// coordinates overlay as views. Interactive: drag a piece, or tap source-then-target → `onMove`.
/// Pure render of its inputs; all color/geometry choices live in `BoardStyle`.
struct SessionBoardView: View {
    let fen: String
    var highlights: [Highlight] = []
    var arrows: [Arrow] = []
    var flipped: Bool = false
    var size: CGFloat = Theme.Size.boardDefault
    var onMove: ((String, String) -> Void)? = nil
    /// Stable per-piece ids keyed by algebraic square (e.g. "d6"), so one physical piece keeps the same
    /// SwiftUI identity across positions and a `withAnimation` fen change SLIDES it. nil → square-keyed
    /// identity (snap) — used for live / non-history positions where no step animation is wanted.
    var pieceIds: [String: String]? = nil

    @State private var picked: String? = nil
    @State private var dragFrom: String? = nil
    @State private var dragAsset: String? = nil
    @State private var dragLocation: CGPoint? = nil

    private var sq: CGFloat { size / 8 }
    private var whiteAtBottom: Bool { !flipped }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                drawSquares(ctx)
                drawHighlights(ctx)
                drawArrows(ctx)
            }
            .frame(width: size, height: size)
            pieceLayer
            coordinateLayer
            dragOverlay
        }
        .frame(width: size, height: size)
        .border(Theme.Palette.ink, width: 1)
        .contentShape(Rectangle())
        .gesture(boardGesture)
        .padding(Theme.Size.boardFramePad)
        .background(
            Theme.Palette.paper
                .overlay(Rectangle().inset(by: 2.5).stroke(Theme.Palette.ink22, lineWidth: 1))
        )
        .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
        .shadow(color: Theme.Palette.ink.opacity(0.5), radius: 18, x: 0, y: 10)
    }

    // MARK: Canvas

    private func drawSquares(_ ctx: GraphicsContext) {
        for r in 0..<8 {
            for c in 0..<8 {
                let rect = CGRect(x: CGFloat(c) * sq, y: CGFloat(r) * sq, width: sq, height: sq)
                let dark = (r + c) % 2 == 1
                ctx.fill(Path(rect), with: .color(dark ? BoardStyle.dark : BoardStyle.light))
                if dark { drawHatch(ctx, in: rect) }
            }
        }
    }

    /// The 45° engraved hatch on dark squares (thin ink lines, ~5px apart).
    private func drawHatch(_ ctx: GraphicsContext, in rect: CGRect) {
        var clipped = ctx
        clipped.clip(to: Path(rect))
        var x = rect.minX - rect.height
        while x < rect.maxX {
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.maxY))
            line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            clipped.stroke(line, with: .color(BoardStyle.hatch), lineWidth: 0.75)
            x += 7
        }
    }

    private func drawHighlights(_ ctx: GraphicsContext) {
        for h in highlights {
            guard let (r, c) = rc(h.square) else { continue }
            let rect = CGRect(x: CGFloat(c) * sq, y: CGFloat(r) * sq, width: sq, height: sq)
            ctx.fill(Path(rect), with: .color(BoardStyle.highlight(h.style)))
        }
        if let picked, let (r, c) = rc(picked) {
            let rect = CGRect(x: CGFloat(c) * sq, y: CGFloat(r) * sq, width: sq, height: sq)
            ctx.fill(Path(rect), with: .color(Theme.Palette.coachBlue.opacity(0.32)))
        }
    }

    private func drawArrows(_ ctx: GraphicsContext) {
        for a in arrows {
            guard let (fr, fc) = rc(a.from), let (tr, tc) = rc(a.to) else { continue }
            let start = CGPoint(x: (CGFloat(fc) + 0.5) * sq, y: (CGFloat(fr) + 0.5) * sq)
            let end = CGPoint(x: (CGFloat(tc) + 0.5) * sq, y: (CGFloat(tr) + 0.5) * sq)
            let color = BoardStyle.arrow(a.style)
            let width = sq * 0.16
            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: end)
            ctx.stroke(shaft, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
            ctx.fill(arrowhead(from: start, to: end, width: width), with: .color(color))
        }
    }

    private func arrowhead(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let len = width * 2.2
        let spread = CGFloat.pi / 7
        var p = Path()
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - len * cos(angle - spread),
                              y: end.y - len * sin(angle - spread)))
        p.addLine(to: CGPoint(x: end.x - len * cos(angle + spread),
                              y: end.y - len * sin(angle + spread)))
        p.closeSubpath()
        return p
    }

    // MARK: overlays

    private var pieceLayer: some View {
        let hidden = dragFrom.flatMap(rc).map { "\($0.0)-\($0.1)" }
        // Identity = a physical piece's STABLE id (one that follows it across plies) when we have one,
        // else the piece's square. Stable ids make a step's moved piece keep its SwiftUI identity between
        // the two positions, so `.position` slides it — with NO per-move remap that could linger and
        // mis-slide an unrelated piece on the next step. This is square- AND timing-independent, so it
        // holds up under fast stepping (unlike the old remap, which raced its own animation).
        let items: [(id: String, p: Placement)] = placements().map { p in
            (pieceIds?[p.square] ?? p.key, p)
        }
        return ForEach(items, id: \.id) { item in
            let p = item.p
            if p.key != hidden {
                Image(p.asset)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: sq * 0.84, height: sq * 0.84)
                    .shadow(color: Theme.Palette.ink.opacity(0.10), radius: 0, x: 0, y: 1)
                    .position(x: (CGFloat(p.c) + 0.5) * sq, y: (CGFloat(p.r) + 0.5) * sq)
                    .transition(.identity)   // pieces appear/vanish instantly — only translation animates

            }
        }
    }

    private var coordinateLayer: some View {
        ForEach(0..<8, id: \.self) { i in
            let file = whiteAtBottom ? i : 7 - i
            let rank = whiteAtBottom ? 8 - i : i + 1
            ZStack {
                Text(String(UnicodeScalar(UInt8(97 + file))))
                    .position(x: (CGFloat(i) + 0.86) * sq, y: 7.85 * sq)
                Text("\(rank)")
                    .position(x: 0.15 * sq, y: (CGFloat(i) + 0.15) * sq)
            }
            .font(Theme.Typography.coordinate)
            .foregroundStyle(Theme.Palette.ink45)
        }
    }

    private var dragOverlay: some View {
        Group {
            if let loc = dragLocation, let asset = dragAsset {
                Image(asset)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: sq * 0.84, height: sq * 0.84)
                    .position(loc)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: interaction

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard onMove != nil, sq > 0 else { return }
                if dragFrom == nil, let s = square(at: value.startLocation),
                   let asset = pieceAsset(at: s) {
                    dragFrom = s; dragAsset = asset
                }
                if dragFrom != nil { dragLocation = value.location }
            }
            .onEnded { value in
                guard onMove != nil, sq > 0 else { return }
                let moved = hypot(value.translation.width, value.translation.height) > sq * 0.4
                defer { dragFrom = nil; dragAsset = nil; dragLocation = nil }
                if moved {
                    if let from = dragFrom, let to = square(at: value.location),
                       from != to, ChessMove.isLegal(fen, from: from, to: to) {
                        picked = nil; onMove?(from, to)
                    }
                } else if let s = square(at: value.location) {
                    handleTap(s)
                }
            }
    }

    private func handleTap(_ target: String) {
        if let from = picked {
            if from != target, isSelfCapture(from, target) { picked = target; return }
            picked = nil
            if from != target, ChessMove.isLegal(fen, from: from, to: target) { onMove?(from, target) }
        } else if pieceAsset(at: target) != nil {
            picked = target
        }
    }

    private func isSelfCapture(_ from: String, _ to: String) -> Bool {
        guard let a = pieceAsset(at: from)?.first, let b = pieceAsset(at: to)?.first else { return false }
        return a == b
    }

    // MARK: geometry

    private func square(at loc: CGPoint) -> String? {
        guard sq > 0 else { return nil }
        let col = Int(loc.x / sq), row = Int(loc.y / sq)
        guard (0..<8).contains(col), (0..<8).contains(row) else { return nil }
        let file = whiteAtBottom ? col : 7 - col
        let rank = whiteAtBottom ? 8 - row : row + 1
        return String(UnicodeScalar(UInt8(97 + file))) + String(rank)
    }

    private func rc(_ square: String) -> (Int, Int)? {
        guard square.count == 2,
              let file = square.first?.asciiValue, (97...104).contains(Int(file)),
              let rank = square.last?.wholeNumberValue, (1...8).contains(rank) else { return nil }
        let f = Int(file) - 97
        let row = whiteAtBottom ? 8 - rank : rank - 1
        let col = whiteAtBottom ? f : 7 - f
        return (row, col)
    }

    private func pieceAsset(at square: String) -> String? {
        guard let (r, c) = rc(square) else { return nil }
        return placements().first { $0.r == r && $0.c == c }?.asset
    }

    private struct Placement: Hashable { let key: String; let square: String; let r: Int; let c: Int; let asset: String }

    private func placements() -> [Placement] {
        let field = fen.split(separator: " ").first.map(String.init) ?? fen
        var out: [Placement] = []
        for (ri, rankStr) in field.split(separator: "/").enumerated() {   // ri 0 = rank 8
            var file = 0
            for ch in rankStr {
                if let n = ch.wholeNumberValue { file += n; continue }
                let asset = (ch.isUppercase ? "w" : "b") + String(ch).uppercased()
                let row = whiteAtBottom ? ri : 7 - ri
                let col = whiteAtBottom ? file : 7 - file
                let square = String(UnicodeScalar(UInt8(97 + file))) + String(8 - ri)   // algebraic, orientation-free
                out.append(Placement(key: "\(row)-\(col)", square: square, r: row, c: col, asset: asset))
                file += 1
            }
        }
        return out
    }
}

// MARK: - presentation

private enum BoardStyle {
    static let light = Theme.Palette.boardLight
    static let dark = Theme.Palette.boardDark
    static let hatch = Theme.Palette.boardHatch

    static func highlight(_ style: String?) -> Color {
        switch style {
        case "gold": return Theme.Palette.gold.opacity(0.38)          // last move
        case "correction": return Theme.Palette.mistakeRed.opacity(0.40)
        case "analysis": return Theme.Palette.coachBlue.opacity(0.32)
        default: return Theme.Palette.coachBlue.opacity(0.30)
        }
    }

    static func arrow(_ style: String?) -> Color {
        switch style {
        case "correction": return Theme.Palette.mistakeRed.opacity(0.85)   // threat
        case "gold": return Theme.Palette.gold.opacity(0.85)
        default: return Theme.Palette.coachBlue.opacity(0.80)              // idea
        }
    }
}
