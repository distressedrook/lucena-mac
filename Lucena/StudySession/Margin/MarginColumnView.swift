import SwiftUI

/// THE MARGIN — the v1 right column, three sections (owner 2026-07-23):
/// the ASSESSMENT badges ("Roughly equal" · "Dynamic"), then WHITE and
/// BLACK scouting reports projected from the deterministic sheet, then the
/// raw JSON at the foot. Paper-and-ink; the numbers are all grounded reads.
struct MarginColumnView: View {
    let content: MarginContent
    var onCommand: (String) -> Void = { _ in }

    @Environment(\.stateStream) private var stream   // the loading cycle's clock
    @State private var showJSON = false
    @State private var breathing = false

    /// The COVER (move 0): only an epigraph, nothing positional or theoretical.
    /// Backend sends just the quote here, so the column shows only that —
    /// centered (owner: "move 0, no positional stuff, just the quote,
    /// centered").
    private var isCover: Bool {
        content.epigraph != nil && content.theory == nil
            && content.sheet == nil && !content.plansPending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.none) {
            status
            if isCover, let e = content.epigraph {
                epigraph(e, centered: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Spacing.lg)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        // AUTHORED content leads the column when present — the
                        // book opens with its epigraph, then names itself.
                        if let e = content.epigraph { epigraph(e) }
                        if let t = content.theory { theoryCard(t) }
                        if content.plansPending {
                            // Only after the rolls does the full screen appear
                            // (owner 2026-07-25); until then the interactive
                            // loading cycles through the pre-roll features.
                            readingPlaceholder
                        } else if let sheet = content.sheet {
                            if let winning = sheet.winning {
                                // outright winning -> only the reason + advice
                                // for the winner (converting) and the defender.
                                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                    Text(winning.reason)
                                        .font(Theme.Typography.restingProse)
                                        .foregroundStyle(Theme.Palette.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    winningTips("CONVERTING", winning.advice)
                                    winningTips("DEFENDING", winning.defense)
                                    if let kb = winning.kingBars, !kb.isEmpty {
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                            Text("KING SAFETY")
                                                .font(Theme.Typography.cardHeading)
                                                .tracking(Theme.Tracking.label)
                                                .foregroundStyle(Theme.Palette.ink45)
                                            ForEach(kb) { StatBar(label: $0.label, value: $0.value, mid: $0.mid) }
                                        }
                                    }
                                }
                            } else {
                                badges(sheet.assessment)
                                statBars
                                SideReportView(title: "White", side: sheet.sides.white)
                                SideReportView(title: "Black", side: sheet.sides.black)
                            }
                        }
                        // no empty-state text: a theory-only or bare column
                        // just shows what it has, nothing more.
                        if content.raw != nil { jsonSection }
                    }
                    .padding(.top, Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
            MarginCommandField(onSubmit: onCommand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: status chrome

    @ViewBuilder private var status: some View {
        if let s = content.statusLine {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(s)
                    .font(Theme.Typography.labelSmall)
                    .tracking(Theme.Tracking.label)
                    .foregroundStyle(content.plansPending
                                     ? Theme.Palette.gold : Theme.Palette.ink45)
                Rectangle().fill(Theme.Palette.ink22).frame(height: 1)
            }
        }
    }

    /// The server's verdict chips. Flow-wrapped so a row of them wraps
    /// instead of clipping; empty when nothing is decisive enough to say.
    @ViewBuilder private var verdictBadges: some View {
        let items = content.sheet?.badges ?? []
        if !items.isEmpty {
            FlowBadges(items: items)
        }
    }

    /// A labeled block of winning/defending tips (server-authored strings).
    @ViewBuilder private func winningTips(_ label: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(label)
                    .font(Theme.Typography.cardHeading)
                    .tracking(Theme.Tracking.label)
                    .foregroundStyle(Theme.Palette.ink45)
                ForEach(Array(items.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text("\u{2022}").foregroundStyle(Theme.Palette.ink45)
                        Text(tip)
                            .font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The labeled 0-1 bars (Eval/Activity/Space centered, king safety
    /// absolute). Comparable quantities only — see the server's _bars_block.
    @ViewBuilder private var statBars: some View {
        let bars = content.sheet?.bars ?? []
        if !bars.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                ForEach(bars) { StatBar(label: $0.label, value: $0.value, mid: $0.mid) }
            }
        }
    }

    // MARK: the loading state

    /// Rolling the position takes a few seconds (engine MultiPV + Maia).
    /// No spinners on paper — the loading state is a LIVE SCAN LOG (owner 2026-07-25: "while that is
    /// streaming, the current loading doesn't cut it"): the actual features
    /// the pre-roll detected, listed as they arrive, with a spotlight that
    /// moves in lockstep with the board highlights (one clock,
    /// stream.marginCycleIdx). Real content, not skeleton blocks — and it
    /// ties the two halves together: the lit line names the lit squares.
    @ViewBuilder private var readingPlaceholder: some View {
        let stages = stream?.marginStages ?? []
        let idx = stages.isEmpty ? 0 : (stream?.marginCycleIdx ?? 0) % stages.count
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Reading the position\u{2026}")
                .font(Theme.Typography.labelSmall)
                .tracking(Theme.Tracking.label)
                // INK, not a gray (owner 2026-07-25). The scan log is real
                // content, not chrome — the breathing opacity below already
                // says "in progress"; a washed-out ink45 said "disabled".
                .foregroundStyle(Theme.Palette.ink)
                .opacity(breathing ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: breathing)
                .onAppear { breathing = true }
                .onDisappear { breathing = false }

            if stages.isEmpty {
                // before the first stage arrives — a single ruled hint of the
                // list that is coming (rare; the pre-roll streams instantly).
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(Theme.Palette.ink12)
                        .frame(width: 120, height: 8)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                        scanRow(s, current: i == idx)
                    }
                }
            }
        }
    }

    /// One feature line in the scan log — a marker (lit gold on the current
    /// one, matching the board's spotlight), the term, and its square count.
    /// Every term is set in INK (owner 2026-07-25: "why is the text color
    /// gray? make it ink") — the spotlight is carried by the GOLD MARKER and
    /// the dot's size, not by dimming the other lines, which read as
    /// unavailable rather than not-current.
    @ViewBuilder private func scanRow(_ s: MarginProgress, current: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Circle()
                .fill(current ? Theme.Palette.gold : Theme.Palette.ink22)
                .frame(width: current ? 6 : 4, height: current ? 6 : 4)
                .frame(width: 8, alignment: .center)
            Text(s.label ?? "")
                .font(Theme.Typography.cardBody)
                .foregroundStyle(Theme.Palette.ink)
            if let n = s.squares?.count, n > 0 {
                Text("\u{00B7} \(n)")
                    .font(Theme.Typography.labelSmall)
                    .foregroundStyle(Theme.Palette.ink45)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.3), value: current)
    }

    // MARK: authored content — the epigraph and the theory card

    /// Move 1: a sourced quote, set as a book's epigraph. Deterministic per
    /// session, so it never churns while you play.
    @ViewBuilder private func epigraph(_ e: Epigraph, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: Theme.Spacing.xxs) {
            Text("\u{201C}\(e.quote)\u{201D}")
                .font(Theme.Typography.epigraph)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("\u{2014} \(e.author)")
                .font(Theme.Typography.epigraphCredit)
                .foregroundStyle(Theme.Palette.ink55)
            if let src = e.source {
                Text(src)
                    .font(Theme.Typography.epigraphCredit)
                    .foregroundStyle(Theme.Palette.ink45)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // the left rule is the margin-note look; a centered cover drops it.
        .padding(.leading, centered ? 0 : Theme.Spacing.sm)
        .overlay(alignment: .leading) {
            if !centered {
                Rectangle().fill(Theme.Palette.ink22).frame(width: 1)
            }
        }
    }

    /// In book: the opening names itself (masthead) and its theory prose
    /// leads — Wikibooks (attributed) when we have it, else our authored
    /// annotation. Paragraphs render as separate blocks.
    @ViewBuilder private func theoryCard(_ t: Theory) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let name = content.masthead {
                Text(name.uppercased())
                    .font(Theme.Typography.masthead)
                    .tracking(Theme.Tracking.label)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let idea = t.idea {
                // Render each paragraph (server splits them with a blank line)
                // as its own block so the theory reads as prose, not one wall.
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(Array(idea.components(separatedBy: "\n\n")
                                    .enumerated()), id: \.offset) { _, para in
                        Text(para)
                            .font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // CC BY-SA credit — required whenever the idea is quoted theory.
            if let attr = t.attribution, let url = URL(string: attr.url) {
                Link(destination: url) {
                    Text(attr.text)
                        .font(Theme.Typography.cardHeading)
                        .tracking(Theme.Tracking.label)
                        .foregroundStyle(Theme.Palette.ink45)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: section 1 — the assessment badges

    @ViewBuilder private func badges(_ a: Assessment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                MarginBadge(text: shortVerdict(a.verdict), strong: true)
                MarginBadge(text: a.character.bucket.capitalized, strong: false)

                if let phase = a.gamePhase { MarginBadge(text: phase.name, strong: false) }
                Spacer(minLength: Theme.Spacing.none)
            }
            verdictBadges
            // "up a pawn now, won't be soon" — the soft-edge caveat, in the
            // mistake-red ink so it reads as a qualifier on the verdict
            if let ms = a.materialStability, ms.soft, let why = ms.why.first {
                Text("\(ms.leader ?? "")'s edge is soft — \(why)")
                    .font(Theme.Typography.aside)
                    .foregroundStyle(Theme.Palette.mistakeRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "The position is roughly equal." -> "Roughly equal"
    private func shortVerdict(_ v: String) -> String {
        var s = v
        for p in ["The position is ", "The game is "] {
            if s.hasPrefix(p) { s.removeFirst(p.count) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return s.isEmpty ? v : s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: section 3 — the raw JSON, collapsed by default

    private var jsonSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showJSON.toggle() } } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(Theme.Glyph.play)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.ink45)
                        .rotationEffect(.degrees(showJSON ? 90 : 0))
                    Text("JSON")
                        .font(Theme.Typography.label)
                        .tracking(Theme.Tracking.label)
                        .foregroundStyle(Theme.Palette.ink55)
                    Spacer(minLength: Theme.Spacing.none)
                }
            }
            .buttonStyle(.plain)
            if showJSON, let raw = content.raw {
                ScrollView(.horizontal) {
                    Text(raw)
                        .font(Theme.Typography.terminal)
                        .foregroundStyle(Theme.Palette.ink70)
                        .textSelection(.enabled)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

// MARK: - One color's report

private struct SideReportView: View {
    let title: String
    let side: Side

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            space
            // EVERY detected plan, under its evidence tag (owner 2026-07-25).
            // The column used to show `plans.filter { verified == true }` plus
            // an "Ideas" box for the advisory tier — so a plan the engine
            // didn't happen to play in this roll simply vanished (the minority
            // attack confirms on ~half the rolls of the same Carlsbad). The
            // tiers come from the server's verdict, never merged.
            planList("Engine confirmed", tier(.engine))
            planList("Strong humans play this", tier(.human))
            planList("Structure suggests this", tier(.structure))
            bulletList("Weaknesses", side.weaknesses)
            breaks
            chips("Trapped", side.trapped.map { "\($0.piece)\($0.square)" })
            chips("Outposts", side.outposts.map { $0.square })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three evidence tiers, read off the server's verdict — the same
    /// split `position_read` prints in the coach's text, so the two surfaces
    /// can never disagree about how good a plan's evidence is.
    private enum Tier { case engine, human, structure }

    private func tier(_ t: Tier) -> [Plan] {
        let engine = ["CONFIRMED-SOUND", "CONFIRMED-SOUND-LATER"]
        let picked: [Plan]
        switch t {
        case .engine:    picked = side.plans.filter { engine.contains($0.verdict ?? "") }
        case .human:     picked = side.plans.filter { $0.verdict == "HUMAN-TYPICAL" }
        // neither leg fired here — plus the advisory tier, which carries no
        // family and so has no engine contract to check by construction.
        case .structure: picked = side.plans.filter {
                             !engine.contains($0.verdict ?? "")
                                 && $0.verdict != "HUMAN-TYPICAL"
                         } + side.advisory
        }
        // corpus effect inside the tier (stable — equal effect keeps the
        // server's own order)
        return picked.enumerated()
            .sorted { a, b in
                let (ea, eb) = (a.element.effect ?? 0, b.element.effect ?? 0)
                return ea == eb ? a.offset < b.offset : ea > eb
            }
            .map(\.element)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title.uppercased())
                .font(Theme.Typography.masthead)
                .tracking(Theme.Tracking.labelWide)
                .foregroundStyle(Theme.Palette.ink)
            Rectangle().fill(Theme.Palette.ink22).frame(height: 1.5)
        }
    }

    // control shares: three thin bars (0.5 = contested)
    @ViewBuilder private var space: some View {
        let regions = ["center", "kingside", "queenside"].compactMap { r in
            side.space?[r].map { (r, $0) }
        }.filter { $0.1.score >= 0.55 || !$0.1.exploitable.isEmpty }
        if !regions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                sectionLabel("Space")
                ForEach(regions, id: \.0) { r, sp in
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(r.capitalized).font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink)
                        if !sp.exploitable.isEmpty {
                            Text("holes " + sp.exploitable.joined(separator: " "))
                                .font(Theme.Typography.cardBody)
                                .foregroundStyle(Theme.Palette.mistakeRed)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var breaks: some View {
        if !side.breaks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                sectionLabel("Breaks")
                ForEach(side.breaks) { b in
                    HStack(spacing: Theme.Spacing.xxs) {
                        MoveChip(text: b.push)
                        Text("hits " + b.targets.joined(separator: " "))
                            .font(Theme.Typography.cardBody)
                            .foregroundStyle(b.playable ? Theme.Palette.ink
                                             : Theme.Palette.ink45)
                        if !b.playable {
                            Text("· prep").font(Theme.Typography.labelSmall)
                                .foregroundStyle(Theme.Palette.ink45)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func planList(_ label: String, _ plans: [Plan]) -> some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                sectionLabel(label)
                ForEach(plans) { p in
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Text("▪").font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink45)
                        Text(p.idea).font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let t = timingTag(p.timing) { MarginBadge(text: t) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func bulletList(_ label: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                sectionLabel(label)
                ForEach(items.prefix(4), id: \.self) { s in
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Text("▪").font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink45)
                        Text(s).font(Theme.Typography.cardBody)
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func chips(_ label: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                sectionLabel(label)
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(items, id: \.self) { MoveChip(text: $0) }
                }
            }
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(Theme.Typography.labelSmall)
            .tracking(Theme.Tracking.label)
            .foregroundStyle(Theme.Palette.ink45)
    }

    private func timingTag(_ t: String?) -> String? {
        switch t {
        case "immediate": return "Short term"
        case "developing", "long-term": return "Long term"
        default: return nil
        }
    }
}

/// A thin labeled bar. `mid` (0.5 for shares) draws a contested midline.
private struct StatBar: View {
    let label: String
    let value: Double
    /// When set (0.5), this is a CENTERED White-minus-Black bar: the fill
    /// runs from the midline OUT toward whoever leads, so a gain for either
    /// side GROWS the bar toward that side (a left fill would instead SHRINK
    /// when Black improves — which read as "activity went down" after ...Nf6).
    /// Absent -> an absolute 0-1 bar (king safety), filled from the left.
    var mid: Double? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label).font(Theme.Typography.cardBody)
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 76, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                if mid != nil {
                    // A chess EVAL BAR: White fills from the left, Black takes
                    // the rest, the boundary IS the advantage (owner: "make it
                    // look like the eval bar — you know white and black"). A
                    // gain for either side grows THAT side's colour; the
                    // midline marks dead even.
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.Palette.ink)              // Black
                        Rectangle().fill(Theme.Palette.chipWhite)        // White
                            .frame(width: w * value)
                        Rectangle().fill(Theme.Palette.ink45)            // even mark
                            .frame(width: 1).offset(x: w * (mid ?? 0.5))
                    }
                } else {
                    // absolute 0-1 (king safety): a single ink fill on paper.
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.Palette.paperDeep)
                        Rectangle().fill(Theme.Palette.ink70)
                            .frame(width: w * value)
                    }
                }
            }
            .frame(height: 7)
            .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
            // trailing: which side leads (centered) or the raw 0-1 (absolute)
            Text(trailing)
                .font(Theme.Typography.cardMove)
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var trailing: String {
        guard let mid else { return String(format: "%.2f", value) }
        if abs(value - mid) < 0.02 { return "=" }
        return value > mid ? "W" : "B"
    }
}

/// A move/square in a white box (the sheet's notation chip).
private struct MoveChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Typography.cardMove)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, Theme.Spacing.xxs)
            .padding(.vertical, 1)
            .background(Theme.Palette.chipWhite)
            .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
    }
}

// MARK: - The printed badge (shared)

struct MarginBadge: View {
    let text: String
    var strong: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.labelSmall)
            .tracking(Theme.Tracking.label)
            .foregroundStyle(strong ? Theme.Palette.ink : Theme.Palette.ink70)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.hair)
            .overlay(Rectangle().stroke(
                strong ? Theme.Palette.ink45 : Theme.Palette.ink22, lineWidth: 1))
    }
}

/// Wrapping row of verdict chips. The margin is narrow, so a plain HStack
/// clips; this lays them out line by line.
private struct FlowBadges: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ForEach(items, id: \.self) { t in
                MarginBadge(text: t, strong: false)
            }
        }
    }
}
