import SwiftUI

/// THE MARGIN — the v1 right column, three sections (owner 2026-07-23):
/// the ASSESSMENT badges ("Roughly equal" · "Dynamic"), then WHITE and
/// BLACK scouting reports projected from the deterministic sheet, then the
/// raw JSON at the foot. Paper-and-ink; the numbers are all grounded reads.
struct MarginColumnView: View {
    let content: MarginContent
    var onCommand: (String) -> Void = { _ in }

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
                        if let sheet = content.sheet {
                            badges(sheet.assessment)
                            statBars
                            SideReportView(title: "White", side: sheet.sides.white)
                            SideReportView(title: "Black", side: sheet.sides.black)
                        } else if content.plansPending {
                            readingPlaceholder
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
    /// No spinners on paper — a breathing line of type and two ruled
    /// placeholder blocks, so the column has the SHAPE of the answer that
    /// is coming instead of collapsing to nothing.
    @ViewBuilder private var readingPlaceholder: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Reading the position\u{2026}")
                .font(Theme.Typography.restingProse)
                .foregroundStyle(Theme.Palette.ink45)
                .opacity(breathing ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: breathing)
                .onAppear { breathing = true }
                .onDisappear { breathing = false }
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Rectangle().fill(Theme.Palette.ink12)
                        .frame(width: 84, height: 9)
                    Rectangle().fill(Theme.Palette.ink12)
                        .frame(maxWidth: .infinity).frame(height: 7)
                    Rectangle().fill(Theme.Palette.ink12)
                        .frame(maxWidth: .infinity).frame(height: 7)
                        .padding(.trailing, Theme.Spacing.xxl)
                }
            }
        }
    }

    // MARK: authored content — the epigraph and the theory card

    /// Move 1: a sourced quote, set as a book's epigraph. Deterministic per
    /// session, so it never churns while you play.
    @ViewBuilder private func epigraph(_ e: Epigraph, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: Theme.Spacing.xxs) {
            Text("\u{201C}\(e.quote)\u{201D}")
                .font(Theme.Typography.epigraph)
                .foregroundStyle(Theme.Palette.ink82)
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
                            .foregroundStyle(Theme.Palette.ink82)
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
            planList("Plans", side.plans.filter { $0.verified == true })
            if !side.advisory.isEmpty { planList("Ideas", side.advisory) }
            bulletList("Weaknesses", side.weaknesses)
            breaks
            chips("Trapped", side.trapped.map { "\($0.piece)\($0.square)" })
            chips("Outposts", side.outposts.map { $0.square })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title.uppercased())
                .font(Theme.Typography.masthead)
                .tracking(Theme.Tracking.labelWide)
                .foregroundStyle(Theme.Palette.ink82)
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
                            .foregroundStyle(Theme.Palette.ink70)
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
                            .foregroundStyle(b.playable ? Theme.Palette.ink70
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
                            .foregroundStyle(Theme.Palette.ink82)
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
                            .foregroundStyle(Theme.Palette.ink70)
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
    var mid: Double? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label).font(Theme.Typography.cardBody)
                .foregroundStyle(Theme.Palette.ink70)
                .frame(width: 76, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Palette.paperDeep)
                    Rectangle().fill(Theme.Palette.ink70)
                        .frame(width: geo.size.width * value)
                    if let mid {
                        Rectangle().fill(Theme.Palette.ink45)
                            .frame(width: 1)
                            .offset(x: geo.size.width * mid)
                    }
                }
            }
            .frame(height: 7)
            .overlay(Rectangle().stroke(Theme.Palette.ink22, lineWidth: 1))
            Text(String(format: "%.2f", value))
                .font(Theme.Typography.cardMove)
                .foregroundStyle(Theme.Palette.ink55)
                .frame(width: 34, alignment: .trailing)
        }
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
            .foregroundStyle(strong ? Theme.Palette.ink82 : Theme.Palette.ink55)
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
