import SwiftUI
import AppKit

/// The move navigator under the board — a single flowing line, PGN-numbered, figurine notation. It
/// shows the mainline, or (when you enter a variation) the FULL line: mainline prefix flowing into the
/// sideline, with a marker at the branch point. A move that hides variations carries a small ↑; tapping
/// it opens a popover to pick one, which replaces the line in place. Back/Cancel walk back out.
struct MoveNavigatorView: View {
    let line: [LineMove]
    let cursor: Int                                        // viewed move index (highlight)
    var inVariation: Bool = false
    var hasVariations: (Int) -> Bool = { _ in false }      // does the move at this line index have alternatives?
    let onSelect: (Int) -> Void                            // jump the board to a line index
    var onCaretTap: (String, Int) -> Void = { _, _ in }    // (move id, line index)
    var onBack: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                        if line.isEmpty {
                            Text(verbatim: "—").font(Theme.Typography.move).foregroundStyle(Theme.Palette.ink45)
                        }
                        ForEach(Array(line.enumerated()), id: \.element.id) { i, move in
                            moveGroup(i, move)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .onChange(of: cursor) { _, i in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(i, anchor: .center) }
                }
            }
            .frame(maxWidth: .infinity)
            if inVariation {
                separator
                iconButton(Theme.Symbol.back, action: onBack)     // pop one level
                separator
                iconButton(Theme.Symbol.cancel, action: onCancel) // back to the mainline
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // hug the strip's height so the buttons match it
    }

    /// A full-height white divider between the strip and the buttons (and between the buttons).
    private var separator: some View {
        Rectangle().fill(Theme.Palette.paper).frame(width: 1.5).frame(maxHeight: .infinity)
    }

    /// A move's optional PGN number + its chip. The root (start position, no move) renders as a "…"
    /// block — the visible origin that first-move variations branch from.
    @ViewBuilder private func moveGroup(_ i: Int, _ move: LineMove) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
            if let label = numberLabel(i, move) {
                Text(verbatim: label)
                    .font(Theme.Typography.move).foregroundStyle(Theme.Palette.ink45)
            }
            chip(i, move)
        }
        .id(i)
        // Both phases are anchored at the origin (leading): on Back the variation moves collapse LEFT
        // into the branch, then the parent continuation emerges from that same origin and animates
        // rightward into place (not flying in from the far right edge).
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    /// "18." before a white move; "18…" before a black move ONLY when it doesn't pair with a white move
    /// just before it. The root "…" block has no number.
    private func numberLabel(_ i: Int, _ move: LineMove) -> String? {
        if move.san == nil && move.uci == nil { return nil }   // the "…" start block
        if move.uci == nil && move.san == "?" { return nil }   // the "?" solve placeholder — no number
        if move.whiteMoved { return "\(move.number)." }
        let pairsWithPriorWhite = i > 0 && line[i - 1].whiteMoved
        return pairsWithPriorWhite ? nil : "\(move.number)…"
    }

    /// The move chip. A move that hides variations gets a gold underline and — tapping ANYWHERE on it —
    /// opens its variation popover (in addition to jumping the board to it).
    private func chip(_ i: Int, _ move: LineMove) -> some View {
        let active = i == cursor
        let hasVars = hasVariations(i)
        return Button {
            onSelect(i)
            if hasVars { onCaretTap(move.id, i) }
        } label: {
            Text(verbatim: MoveListStyle.figurine(move.san ?? move.uci ?? "…"))   // root → "…" start block
                .font(Theme.Typography.move)
                .foregroundStyle(active ? Theme.Palette.paper : Theme.Palette.ink)
                .padding(.vertical, Theme.Spacing.xxs).padding(.horizontal, Theme.Spacing.xs)
                .background(active ? Theme.Palette.ink : Color.clear)
                .overlay(alignment: .bottom) {          // gold underline marks a move that hides variations
                    if hasVars {
                        Rectangle().fill(Theme.Palette.gold).frame(height: 1.5)
                            .padding(.horizontal, Theme.Spacing.xs)
                    }
                }
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CaretAnchorKey.self, value: .bounds) { hasVars ? [move.id: $0] : [:] }
    }

    /// An icon-only, full-height nav button (Back / Cancel).
    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.paper)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, Theme.Spacing.md)
                .background(Theme.Palette.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One row of the variation picker — styled like the settings menu's rows (hover, uppercase, divider).
/// A `wrong` row carries the same red ✗ badge the chat pane shows on a mistaken move.
private struct VariationRow: View {
    let text: String
    let divider: Bool
    var wrong: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if wrong { wrongBadge }
                Text(verbatim: text)
                    .font(Theme.Typography.move)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9).padding(.horizontal, 14)
                .background(hovering ? Theme.Palette.paperDeep : Theme.Palette.paper)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if divider { Rectangle().fill(Theme.Palette.ink.opacity(0.16)).frame(height: 1) }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    // Matches the chat's verdict cross: a small red square with a paper xmark.
    private var wrongBadge: some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.Palette.paper)
            .frame(width: 14, height: 14)
            .background(Theme.Palette.mistakeRed)
    }
}

/// While `active`, fires `onDown` on every mouse-down WITHOUT consuming the event — so a click off the
/// variation card can dismiss it and still perform its own action (play a move, step, etc.) in one go.
struct GlobalMouseDownDismiss: NSViewRepresentable {
    var active: Bool
    var onDown: () -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDown = onDown
        context.coordinator.setActive(active)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var onDown: () -> Void = {}
        private var monitor: Any?
        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
                    self?.onDown(); return e     // never consume — the click still lands on whatever's under it
                }
            } else if !active, let m = monitor {
                NSEvent.removeMonitor(m); monitor = nil
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

/// Reports each caret's bounds so the screen can float the variation menu right above it (a custom
/// card, not a system popover). Keyed by move id; first-writer wins on a merge.
struct CaretAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

/// The variation picker — a custom floating card (NOT a system popover), styled exactly like the
/// settings menu: hard-edged paper with an offset ink shadow, one PGN-numbered row per variation.
struct VariationMenu: View {
    let nodes: [VarNode]
    var backLabel: String? = nil          // when in a variation: "← <the line it branched from>"
    var isWrong: (VarNode) -> Bool = { _ in false }   // this variation is a mistaken try → red ✗
    let onPick: (VarNode) -> Void
    var onBack: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let backLabel {
                VariationRow(text: "←  " + backLabel, divider: !nodes.isEmpty, action: onBack)
            }
            ForEach(Array(nodes.enumerated()), id: \.element.id) { j, node in
                VariationRow(text: MoveListStyle.numbered(node.line), divider: j < nodes.count - 1,
                             wrong: isWrong(node)) {
                    onPick(node)
                }
            }
        }
        .frame(minWidth: 150, alignment: .leading)
        .background(Theme.Palette.paper)
        .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
        .background(Rectangle().fill(Theme.Palette.ink).offset(x: 3, y: 3))   // hard offset shadow
        .fixedSize()
    }
}
