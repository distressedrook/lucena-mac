import Foundation
import SwiftUI

/// The coach's voice — beats stream top-to-bottom, the active (newest) beat carries a blue
/// left-rule at full opacity, past beats fade behind a faint ink rule. A beat may carry an
/// inline "you" reply (the player's words, right-aligned).
struct BeatsColumnView<Footer: View>: View {
    let beats: [Beat]
    let history: [Ply]                  // to link a move NAMED in prose to the position it produced
    let onMoveTap: (String) -> Void     // tap a move chip → snap the board to that position (by fen)
    let onCardTap: (Int) -> Void        // tap an activity card → reopen that saved activity (by idx)
    let scrollAnchor: UnitPoint         // .bottom follows the newest beat (live); .top opens at the start (review)
    let footer: () -> Footer            // action buttons that flow at the END of the conversation

    init(beats: [Beat], history: [Ply] = [], onMoveTap: @escaping (String) -> Void = { _ in },
         onCardTap: @escaping (Int) -> Void = { _ in }, scrollAnchor: UnitPoint = .bottom,
         @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.beats = beats
        self.history = history
        self.onMoveTap = onMoveTap
        self.onCardTap = onCardTap
        self.scrollAnchor = scrollAnchor
        self.footer = footer
    }

    var body: some View {
        // Chat/terminal scroll (macOS 14+): `defaultScrollAnchor(.bottom)` opens at the newest beat and
        // FOLLOWS new content while the reader is at the bottom, but leaves a scrolled-up reader exactly
        // where they are. It replaces a ScrollViewReader that fired `scrollTo` on a stack of timers on
        // every beat/text change — which fought an active drag (a `scrollTo` mid-drag can snap the view
        // to the top) and made the panel feel stuck. Let the framework own the anchor; don't chase it.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // A neutral move beat ("1. e4" on its own line) is dropped: the coach's own narration
                // that follows always names the move inline as a chip, so the standalone header only
                // repeated it a beat later.
                ForEach(beats.filter { !$0.isNeutralMove }) { beat in
                    BeatRow(beat: beat, active: beat.id == beats.last?.id, moveLookup: moveLookup,
                            onMoveTap: onMoveTap, onCardTap: onCardTap)
                        .id(beat.id)
                        // Beats fade in, calmly. (An earlier version slid player beats from the right and
                        // coach beats from the left; combined with a whole-conversation reload on an
                        // activity switch that read as "things flying in from everywhere". One direction —
                        // none — is quieter, and the pane itself does the left↔right slide on a switch.)
                        .transition(.opacity)
                }
                footer()                                        // Retry / show-me-the-trap, in-flow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, Theme.Spacing.xs)
        }
        .defaultScrollAnchor(scrollAnchor)
    }

    /// Every ACTUAL move in the game, keyed by how the coach numbers it in prose ("12. Nf3",
    /// "12... Nf3" — see `_numbered` backend-side) so a mention mid-sentence can be linked to the
    /// position it produced. Built ONLY from played history, never from a typical-reply/hypothetical
    /// move mentioned in the same beat: those were never played, so there is no fen to snap to, and a
    /// mention that doesn't match an actual ply here correctly stays plain, unlinked text.
    private var moveLookup: [String: String] {
        var out: [String: String] = [:]
        for ply in history {
            guard ply.n > 0, let san = ply.san, !san.isEmpty else { continue }
            let moveNum = (ply.n + 1) / 2
            out[ply.n % 2 == 1 ? "\(moveNum). \(san)" : "\(moveNum)... \(san)"] = ply.fen
        }
        return out
    }
}

private struct BeatRow: View {
    let beat: Beat
    let active: Bool
    var moveLookup: [String: String] = [:]
    var onMoveTap: (String) -> Void = { _ in }
    var onCardTap: (Int) -> Void = { _ in }

    var body: some View {
        if beat.isCard {
            ActivityCardView(title: beat.title ?? "Puzzle", status: beat.status,
                             kind: beat.activityKind ?? "puzzle") {
                if let idx = beat.activityIdx { onCardTap(idx) }
            }
        } else if beat.isYou {
            youBubble(beat.text, correct: beat.correct, move: beat.move, fen: beat.fen)
        } else if beat.isOpp {
            // Lucena playing the opponent's reply — the coach's LEFT-rule + label (like any coach beat),
            // with the SAME "Played [chip]" as the player's move, but no verdict tick (it isn't judged).
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(active ? Theme.Palette.coachBlue : Theme.Palette.ink18)
                    .frame(width: 2.5)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    label
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(Strings.StudySession.played)
                            .font(Theme.Typography.coachBody).foregroundStyle(Theme.Palette.ink82)
                        if let move = beat.move, let fen = beat.fen {
                            moveChip(move) { onMoveTap(fen) }        // clickable, no tick
                        }
                    }
                }
                .padding(.leading, Theme.Spacing.lg)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(active ? Theme.Palette.coachBlue : Theme.Palette.ink18)
                    .frame(width: 2.5)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    label
                    BeatStyle.body(beat.segments, moveLookup: moveLookup, onMoveTap: onMoveTap)
                        .font(Theme.Typography.coachBody)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let you = beat.you {
                        youBubble(you, correct: nil, move: nil, fen: nil)
                    }
                }
                .padding(.leading, Theme.Spacing.lg)
            }
        }
    }

    private var label: some View {
        Text(Strings.StudySession.coachName)
            .font(Theme.Typography.labelSmall)
            .tracking(Theme.Tracking.labelWide)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.ink70)
    }

    private func youBubble(_ text: String, correct: Bool?, move: String?, fen: String?) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
            Text(Strings.StudySession.youLabel)
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.labelWide)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink45)
            HStack(spacing: Theme.Spacing.xs) {
                if let move, let fen {                     // a played move → clickable navigator-style chip
                    Text(Strings.StudySession.played)
                        .font(Theme.Typography.coachBody).foregroundStyle(Theme.Palette.ink82)
                    HStack(spacing: 0) {                   // verdict badge ABUTS the move — a stamp on it
                        moveChip(move) { onMoveTap(fen) }
                        if let correct { verdictBadge(correct) }   // green check / red cross, touching
                    }
                    if let sfx = suffix(of: text, after: move), !sfx.isEmpty {
                        Text(verbatim: sfx)
                            .font(Theme.Typography.coachBody).foregroundStyle(Theme.Palette.ink82)
                    }
                } else {
                    if let correct { verdictBadge(correct) }   // no move (typed answer) → badge stands alone
                    Text(text)                             // plain text, no bubble box; same size as the coach
                        .font(Theme.Typography.coachBody)
                        .foregroundStyle(Theme.Palette.ink82)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, Theme.Spacing.xxs)
    }

    /// The played move as a boxed chip — styled like the navigator's SELECTED move: a solid black box
    /// with the figurine glyph in light, in the navigator's move font. Tapping snaps the board there.
    private func moveChip(_ move: String, action: @escaping () -> Void) -> some View {
        Text(verbatim: MoveListStyle.figurine(move))
            .font(Theme.Typography.move)
            .foregroundStyle(Theme.Palette.paper)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(height: Self.badgeSide)             // match the verdict badge so they abut flush
            .background(Theme.Palette.ink)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    /// The echo text after the move token ("Played Qf3+ — takes the bishop" → " — takes the bishop").
    private func suffix(of text: String, after move: String) -> String? {
        guard let r = text.range(of: move) else { return nil }
        return String(text[r.upperBound...])
    }

    /// The drill verdict next to a played move: a solid square — green with a check (right) or red with
    /// a cross (wrong). Replaces the canned "That's right!" / "not quite" feedback beat.
    private static let badgeSide: CGFloat = 24          // shared by the move chip so the two abut flush

    private func verdictBadge(_ correct: Bool) -> some View {
        Image(systemName: correct ? "checkmark" : "xmark")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.Palette.paper)
            .frame(width: Self.badgeSide, height: Self.badgeSide)
            .background(correct ? Theme.Palette.correctGreen : Theme.Palette.mistakeRed)
    }
}

// MARK: - activity card

/// A saved activity (a puzzle the player attempted) as a clickable card in the base conversation.
/// Tapping it reopens that activity — its own board, beats and variations. The "Annotated Board"
/// look: paper + ink, no gradients; the status reads "attempted" or "solved".
private struct ActivityCardView: View {
    let title: String
    let status: String?
    let kind: String
    let onTap: () -> Void

    private var solved: Bool { status == "solved" }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                statusBadge                       // SQUARE, per design (matches the verdict tick)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.serif(16, .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(solved ? "Solved · tap to review" : "Attempted · tap to review")
                        .font(Theme.Typography.labelSmall)
                        .tracking(Theme.Tracking.labelWide)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Palette.ink45)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink45)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.paper)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Palette.ink18, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// The status indicator — a SQUARE (the design's verdict-badge shape, never a rounded seal): a
    /// green square with a paper checkmark when solved, an ink-outlined empty square when only attempted.
    private var statusBadge: some View {
        ZStack {
            if solved {
                Rectangle().fill(Theme.Palette.correctGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.Palette.paper)
            } else {
                Rectangle().stroke(Theme.Palette.ink45, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - presentation

private enum BeatStyle {
    /// Render a beat's segments. Two paths:
    /// - Any segment carries a structured `tone` (`em` → blue italic, `mark` → red bold): the
    ///   legacy inline path, concatenated into one `Text`. Tone is a backend-assigned fact, not
    ///   something a reader typed — it isn't Markdown and shouldn't be re-parsed as such.
    /// - Otherwise (the normal coaching/narration path today): the segments' text is joined and
    ///   read as light Markdown — paragraphs, "- " bullet lists, **bold**/*italic* — which is
    ///   what the orchestrator's prompts are told they may use (see `_MARKDOWN_RULE`).
    @ViewBuilder
    static func body(_ segments: [Segment], moveLookup: [String: String],
                     onMoveTap: @escaping (String) -> Void) -> some View {
        if segments.contains(where: { $0.tone != nil }) {
            legacyInline(segments)
        } else {
            richText(segments.map(\.text).joined(), moveLookup: moveLookup, onMoveTap: onMoveTap)
        }
    }

    private static func legacyInline(_ segments: [Segment]) -> Text {
        segments.reduce(Text(verbatim: "")) { acc, seg in acc + run(seg) }
    }

    private static func run(_ seg: Segment) -> Text {
        switch seg.tone {
        case "em":
            return Text(seg.text).italic().foregroundColor(Theme.Palette.coachBlue)
        case "mark":
            return Text(seg.text).bold().foregroundColor(Theme.Palette.mistakeRed)
        default:
            return Text(seg.text)
        }
    }

    // MARK: - light Markdown

    /// A block of prose: either a paragraph or a run of consecutive "- "/"* " bullet lines.
    private enum Block {
        case paragraph(String)
        case list([String])
    }

    /// Blank lines (`\n\n`, however the model spaced them) separate paragraphs; within a
    /// paragraph, a leading "- "/"* " on a line starts a bullet list that swallows every
    /// following bulleted line, so a paragraph can be prose, a list, or prose-then-list.
    private static func parseBlocks(_ raw: String) -> [Block] {
        var blocks: [Block] = []
        for paragraph in raw.components(separatedBy: "\n\n") {
            var proseLines: [String] = []
            var listItems: [String] = []
            func flushProse() {
                if !proseLines.isEmpty { blocks.append(.paragraph(proseLines.joined(separator: "\n"))) }
                proseLines = []
            }
            func flushList() {
                if !listItems.isEmpty { blocks.append(.list(listItems)) }
                listItems = []
            }
            for line in paragraph.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    flushProse()
                    listItems.append(String(trimmed.dropFirst(2)))
                } else {
                    flushList()
                    proseLines.append(String(line))
                }
            }
            flushList()
            flushProse()
        }
        return blocks
    }

    private static func richText(_ raw: String, moveLookup: [String: String],
                                 onMoveTap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(parseBlocks(raw).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    paragraph(text, moveLookup: moveLookup, onMoveTap: onMoveTap)
                case .list(let items):
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                Text("•")
                                paragraph(item, moveLookup: moveLookup, onMoveTap: onMoveTap)
                            }
                        }
                    }
                }
            }
        }
    }

    /// One paragraph/list-item as a WRAPPING flow of word-tokens and move chips — not a single `Text`.
    /// `Text` can only wrap its OWN characters; it cannot embed an arbitrary child view (a chip with a
    /// background box, per the design — not achievable with a Markdown `.link` run, which has no
    /// per-run background) inline within that wrap. So prose containing a move is laid out word-by-word
    /// here instead, in `FlowLayout`, and everything else (**bold**, *italic*) rides along per-word.
    private static func paragraph(_ raw: String, moveLookup: [String: String],
                                  onMoveTap: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(Array(MoveLink.tokenize(raw, lookup: moveLookup).enumerated()), id: \.offset) { _, token in
                switch token {
                case .word(let attributed):
                    Text(attributed)
                case .move(let label, let fen):
                    moveChip(label, fen: fen, onMoveTap: onMoveTap)
                }
            }
        }
    }

    /// A move NAMED in prose, styled exactly like the navigator's / "you played" chip (solid ink box,
    /// paper figurine text) — the same component, not a lookalike, so a reader learns the ONE shape
    /// that means "tap this to jump the board" and it means the same thing everywhere it appears.
    private static func moveChip(_ label: String, fen: String, onMoveTap: @escaping (String) -> Void) -> some View {
        Text(verbatim: MoveListStyle.figurineNumbered(label))
            .font(Theme.Typography.move)
            .foregroundStyle(Theme.Palette.paper)
            .padding(.vertical, Theme.Spacing.xxs)
            .padding(.horizontal, Theme.Spacing.xs)
            .background(Theme.Palette.ink)
            .contentShape(Rectangle())
            .onTapGesture { onMoveTap(fen) }
    }
}

// MARK: - linking a move NAMED in prose to the position it produced

/// Finds numbered-move mentions ("12. Nf3", "12... Nf3" — the exact shape the backend's `_numbered`
/// always emits, see CLAUDE.md "Prompts are first-class citizens") inside a block of prose, and turns
/// the ones that match an ACTUAL played ply into a `.move` token carrying that ply's fen. A move
/// mentioned that was NOT actually played (a typical reply, a refutation line, "the engine's best move
/// is...") has no entry in the lookup and comes back as plain `.word` tokens instead: there is no board
/// position to send a tap to, so it must not look tappable.
private enum MoveLink {
    enum Token {
        case word(AttributedString)
        case move(label: String, fen: String)
    }

    static func tokenize(_ raw: String, lookup: [String: String]) -> [Token] {
        guard !lookup.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"\d+\.{1,3}\s*[A-Za-z][A-Za-z0-9+#=\-]*"#)
        else { return words(of: raw) }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return words(of: raw) }
        var tokens: [Token] = []
        var cursor = 0
        for m in matches {
            tokens += words(of: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            let matched = ns.substring(with: m.range)
            if let key = canonicalKey(matched), let fen = lookup[key] {
                tokens.append(.move(label: matched, fen: fen))
            } else {
                tokens += words(of: matched)   // no such ply — falls back to plain word(s), not a chip
            }
            cursor = m.range.location + m.range.length
        }
        tokens += words(of: ns.substring(from: cursor))
        return tokens
    }

    /// Markdown-parses the whole chunk FIRST — so a "**two words**" span keeps its bold attribute
    /// across both — THEN splits the result at whitespace into the individual word tokens `FlowLayout`
    /// actually wraps. Splitting the raw STRING first and parsing each word alone would cut a `**`/`*`
    /// pair in half whenever the emphasis spans more than one word.
    private static func words(of text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
        return attributed.words().map { .word($0) }
    }

    /// "3. Qxd4" / "3...Qxd4" / "3.  Qxd4" → the canonical "3. Qxd4" / "3... Qxd4" the lookup table is
    /// keyed with (one space, matching `_numbered`) — robust to the model's own minor spacing drift,
    /// same reasoning as `_numbered_line`'s comment on why this is computed, never left to the model.
    private static func canonicalKey(_ matched: String) -> String? {
        guard let dotsRange = matched.range(of: #"\.{1,3}"#, options: .regularExpression) else { return nil }
        let num = matched[matched.startIndex..<dotsRange.lowerBound]
        let dotCount = matched.distance(from: dotsRange.lowerBound, to: dotsRange.upperBound)
        let san = matched[dotsRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !san.isEmpty else { return nil }
        switch dotCount {
        case 1: return "\(num). \(san)"
        case 3: return "\(num)... \(san)"
        default: return nil   // "N.." never a real number of dots the backend emits — not a move
        }
    }
}

private extension AttributedString {
    /// Splits at whitespace into individual words, each keeping whatever attributes (bold/italic run,
    /// from Markdown parsing upstream) its characters already had — the unit `FlowLayout` wraps, since
    /// `Text` can only auto-wrap within a SINGLE `Text`, not across the several this view now uses.
    func words() -> [AttributedString] {
        var result: [AttributedString] = []
        var wordStart: AttributedString.Index?
        var idx = startIndex
        while idx < endIndex {
            if characters[idx].isWhitespace {
                if let start = wordStart { result.append(AttributedString(self[start..<idx])); wordStart = nil }
            } else if wordStart == nil {
                wordStart = idx
            }
            idx = index(afterCharacter: idx)
        }
        if let start = wordStart { result.append(AttributedString(self[start..<endIndex])) }
        return result
    }
}

/// A left-to-right, top-to-bottom wrapping layout for mixed text/chip content — SwiftUI's `Text` can
/// only wrap its OWN characters; it cannot embed an arbitrary child view (a move chip) inline within
/// that wrap. Beat prose that contains one is laid out word-by-word here instead, wrapping like a
/// normal paragraph but with a chip sitting among the words wherever one belongs.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        y += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
