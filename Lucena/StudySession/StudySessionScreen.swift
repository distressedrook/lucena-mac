import SwiftUI

/// The Study Session — the hero coaching surface: the mode rail, the masthead, the board beside
/// the coach's beats, with the terminal at the foot of the beats column. Renders entirely off the
/// live `StateStream` and the server (no placeholder data). Owns only UI-local state.
struct StudySessionScreen: View {
    @Environment(\.stateStream) private var stream
    @Environment(\.coachBridge) private var coach

    @State private var mode: RailMode = .study
    @State private var flipped = false
    @State private var engineOn = true
    @State private var settingsOpen = false
    // The coach session id (server-owned), resolved on appear. Held here — the common ancestor of
    // the rail (starts/switches one) and the terminal (runs claude on it) — so the rail swaps it.
    @State private var session: String?
    @State private var rightTab: RightTab = .coach
    @State private var viewIndex: Int?             // move-navigator cursor; nil = live (latest ply)
    @State private var heldWrong: String?          // a wrong drill move, held on the board until Retry
    @State private var solveFen: String?           // the position to return to on Retry (survives coach repaints)
    @State private var lastMoveWrong = false       // the server said the last move was wrong → show Retry
    @State private var lastMoveUci: String?        // the held wrong move (uci) — for the on-demand "Why?"
    @State private var expectCoachBeat = true      // a MOVE produces no coach beat now (✓+local praise /
                                                   // ✗+Why?) — only a text turn / Why? expects one, so the
                                                   // silent-turn "Uh oh" net must skip moves
    @State private var walker: DrillWalker?        // local mirror of the tree → instant ✓/✗ (backend confirms)
    @State private var localLine: [Ply]?           // client-owned move line during a local drill (nil = server's)
    @State private var continueBranchPending = false   // a branch is solved; opponent has other defences → Continue
    @State private var pendingPromotion: PendingPromotion?   // a pawn hit the last rank → pick a piece
    @State private var drillBottomBlack: Bool?     // solver's side, captured from a drill; stays stable
    @State private var analysisOn = true           // the Analysis tab's live-engine toggle
    @State private var analyzeTask: Task<Void, Never>?   // debounces /analyze as the position changes
    @State private var hadPoisonedLine = false           // saw a trap during this drill → offer to punish it on solve
    @State private var poisonedLineNudge = false         // show the post-solve "punish the trap?" nudge
    @State private var baseConceptClosed = false         // a base-frame drill just closed → offer "back to the previous concept" (→ start)
    // Feature flag (disabled for now): the "Back to the previous concept" action buttons (rabbit-hole
    // pop + base-frame reset-to-start). Flip to true to bring them back — the underlying popActivity /
    // resetToStart wiring is untouched.
    private static let showBackToPreviousConcept = false
    // The poisoned line itself (full {uci,san,fen} move sequence) + the position it branches from —
    // LATCHED when detected, because the board clears it on the next repaint (so it's long gone by the
    // post-solve moment the player clicks "Show me the poisoned line").
    @State private var latchedPoisonedLine: [BoardState.PoisonedMove]? = nil
    @State private var latchedPoisonedFrom: String? = nil
    @State private var coachSending = false                // a /turn is in flight → the coach is thinking
    @State private var conversationStarted = false         // player typed/sent → dismiss the starter tips (one-way)
    // Backend-driven: the coach is "working" while the server holds a status up (published for the
    // whole turn, cleared after the beat). Not `coachSending` — that clears the instant the WS send
    // returns, before the beat arrives, which flashed the "Uh oh" fallback and skipped the halo.
    private var coachWorking: Bool { stream?.coachStatus != nil }   // drives the board halo + status row
    @State private var beatsAtWorkStart = 0         // beat count when the coach started → detect a silent turn
    @State private var activityAtWorkStart = 0      // active-activity idx when the coach started → a switch ≠ silent
    private let evalGearRowH: CGFloat = 22          // the settings strip above the board; beats matches it
    @State private var sessionOrder: [String] = []  // frozen rail order — sorted by recency once, then stable
    @State private var shownEvalFraction: Double = 0.5   // held eval fill — animates, never snaps to parity
    @State private var shownEvalText: String = ""
    @State private var pieceIdMaps: [[String: String]] = []   // per-ply stable piece ids (algebraic square -> id)
    // Variations: the user's "what if" lines. When `varStack` is non-empty the strip shows the FULL
    // line (mainline prefix → the chosen sidelines), `varCursor` is the viewed move within it, and Back
    // pops one segment / Cancel clears to the mainline. Empty stack → plain mainline browsing.
    @State private var variations = VariationForest()
    @State private var varStack: [VarSegment] = []
    @State private var varCursor: Int = 0
    @State private var collapseTo: Int? = nil             // Back phase 1: truncate the line to this index
    @State private var openCaret: OpenCaret? = nil        // the caret whose variation menu is floating
    @State private var hoveringPopover = false            // cursor is over the variation card (don't dismiss)
    // Multi-defence "Continue": the opponent's other defences are drilled as SIDE-LINES. When you click
    // Continue the sibling defence opens as a variation you're IN and solving (the mainline stays the
    // line you already solved). `solvingSiblingBranch` routes board moves through the drill adjudicator
    // into that variation — where a wrong move holds + parks under "?", exactly like the mainline.
    @State private var solvingSiblingBranch = false
    // The tree's accepted student move(s) at each position (normalized fen -> uci set), built from the
    // PuzzleDoc when a drill loads. A variation whose move isn't the accepted move at the spot it
    // branches from IS a wrong try — so "wrongness" is DERIVED (no persisted flag) and survives reopen
    // for free, since the tree is re-downloaded every time.
    @State private var solutionUci: [String: Set<String>] = [:]

    struct OpenCaret { let id: String; let index: Int; let nodes: [VarNode]; var backLabel: String? = nil; var branchFen: String = "" }
    @FocusState private var boardFocused: Bool     // arrow keys navigate when the board holds focus

    // The MCP owns the board: it walks the drill tree, advances on a correct move, holds on a wrong
    // one, and pushes every beat. The app just renders the stream; before the coach sets a board we
    // show the opening (the honest "no game yet" state), never a stand-in position.
    private var board: BoardState? { stream?.board }
    // During a local drill the CLIENT owns the move line (`localLine`) — it plays the student's move +
    // the opponent's reply into it with no `/move` round-trip. Otherwise it's the server's line.
    private var history: [Ply] { localLine ?? (stream?.history ?? []) }
    private var liveIndex: Int { max(0, history.count - 1) }     // the latest ply
    private var currentPlyIndex: Int { viewIndex ?? liveIndex }  // the ply being viewed/highlighted
    private var isViewingHistory: Bool { viewIndex != nil }
    private var isInVariation: Bool { !varStack.isEmpty }        // exploring a "what if" line off the mainline
    // A drill answer typed INTO a sibling variation: we're solving that branch and sitting at its tip
    // (its own move to find), so the move goes through the adjudicator, not the explore path.
    private var drillMoveInVariation: Bool {
        solvingSiblingBranch && isInVariation && varCursor == displayLine.count - 1
    }

    /// The side-to-move character ('w'/'b') of a FEN.
    private func sideChar(_ fen: String) -> Character? {
        fen.split(separator: " ").dropFirst().first?.first
    }
    /// The solver's side in a puzzle: whoever is to move at the ROOT (a puzzle always starts on the
    /// solver's move). Nil outside a puzzle, so freeform keeps both sides movable.
    private var solverSide: Character? {
        guard drillGoverns, let root = history.first?.fen else { return nil }
        return sideChar(root)
    }
    /// In a puzzle, is it the OPPONENT's turn at the shown position? Their moves are the fixed line —
    /// the board must be read-only for them; you only ever input moves as the solver.
    private var opponentToMoveInPuzzle: Bool {
        guard let solver = solverSide, let cur = sideChar(displayedFen) else { return false }
        return cur != solver
    }

    /// While solving, the position awaiting the answer (the live tip) — but ONLY when wrong tries are
    /// parked there. That's where the "?" placeholder + its wrong-variation caret live, until the correct
    /// move is played, at which point the wrong tries become the caret siblings of the real move (the
    /// forest is position-keyed, so that resolution is automatic).
    private var solvingFen: String? {
        guard drillGoverns else { return nil }
        // Must be sitting at the LIVE solving tip (not browsing back): the mainline tip, or — when
        // drilling a sibling side-line — that side-line's tip. Wrong tries park there under the "?".
        if isInVariation {
            guard solvingSiblingBranch, varCursor == displayLine.count - 1 else { return nil }
        } else {
            guard !isViewingHistory else { return nil }
        }
        guard let tip = displayLine.last?.fen, variations.has(tip) else { return nil }
        return tip
    }
    /// The strip's line plus a trailing "?" placeholder for the not-yet-played correct move, shown when
    /// wrong tries are parked at the solving position. Display-only — navigation math still uses displayLine.
    private var navigatorLine: [LineMove] {
        guard let solve = solvingFen else { return displayLine }
        return displayLine + [LineMove(id: "solve-placeholder", san: "?", uci: nil, fen: solve,
                                       isBranch: false, node: nil, mainPly: nil)]
    }
    /// Index of the "?" placeholder in `navigatorLine` (-1 when there is none).
    private var placeholderIndex: Int { solvingFen == nil ? -1 : displayLine.count }

    /// Build the full line for a given segment stack: the mainline prefix flowing into each chosen
    /// sideline (divergence move flagged `isBranch`). `varStack` gives the shown line; a shorter stack
    /// gives a parent line (used to label the "back" entry in a variation's popover).
    private func buildLine(_ stack: [VarSegment]) -> [LineMove] {
        var out = history.enumerated().map { i, p in
            LineMove(id: "m\(i)", san: p.san, uci: p.uci, fen: p.fen, isBranch: false, node: nil, mainPly: i)
        }
        for seg in stack {
            let keep = min(max(seg.branchLineIndex + 1, 0), out.count)
            let segMoves = seg.nodes.enumerated().map { j, node in
                LineMove(id: node.id.uuidString, san: node.san, uci: node.uci, fen: node.fen,
                         isBranch: j == 0, node: node, mainPly: nil)
            }
            out = Array(out.prefix(keep)) + segMoves
        }
        return out
    }
    /// The line shown in the strip.
    private var displayLine: [LineMove] {
        var out = buildLine(varStack)
        if let c = collapseTo { out = Array(out.prefix(max(c + 1, 0))) }   // Back phase 1: hide past the branch
        return out
    }
    /// The viewed move's index within `displayLine` (drives the highlight and the board).
    private var lineCursor: Int {
        isInVariation ? min(max(varCursor, 0), max(0, displayLine.count - 1)) : currentPlyIndex
    }

    // Board precedence: an active variation > browsing history > a held wrong move > the Retry solve
    // position (after Retry, preserved even if the coach repaints) > the live board.
    private var displayedFen: String {
        // A wrong try inside a sibling side-line holds optimistically, just like the mainline — show it
        // over the side-line tip (else the variation branch below would swallow the hold).
        if solvingSiblingBranch, let held = heldWrong { return held }
        if isInVariation {
            let l = displayLine
            return l.indices.contains(varCursor) ? l[varCursor].fen : (board?.fen ?? BoardState.startFEN)
        }
        if let i = viewIndex, history.indices.contains(i) { return history[i].fen }
        if let held = heldWrong { return held }
        if let solve = solveFen { return solve }
        // At the live tip, the current position IS the last move played — trust the move line, not a
        // possibly-stale reported board (a mount-time `/position(start)` could otherwise leave the board
        // on the start square while the navigator sits on the last move → they disagree). A freeform /
        // pasted position has no history, so it falls through to the reported board.
        return history.last?.fen ?? board?.fen ?? BoardState.startFEN
    }
    // Orientation is STABLE: in a drill it's the solver's side (captured once, kept even after the
    // drill ends — so the winning move doesn't flip the board); otherwise the side to move from the
    // FEN. The manual flip toggle inverts it.
    private var boardFlipped: Bool {
        // Anchor on the LINE'S STARTING position, never the current one — mid-line (or resumed) the
        // side to move alternates every ply, which flipped the board on relaunch.
        let anchorFen = history.first?.fen ?? board?.fen
        let bottomBlack = drillBottomBlack ?? (anchorFen?.split(separator: " ").dropFirst().first == "b")
        return bottomBlack != flipped
    }
    // Whatever colour sits at the bottom IS the player, full stop — "I"/"me" in chat means this,
    // regardless of whose turn it is or who moved last (the coach grounds pronoun resolution on it;
    // see CoachPrompt.frame server-side). Reported to the backend via /view so it isn't a guess.
    private var povColor: String { boardFlipped ? "black" : "white" }
    // The eval bar's source: the live analyzer's top line for the CURRENT position (white-relative).
    private var liveEval: (cp: Int, winPct: Double)? {
        guard let el = stream?.engineLines, el.fen == displayedFen, let top = el.lines.first else { return nil }
        return (top.evalWhiteCp, top.winPct)
    }
    // The best eval available for the position on screen, or nil if none yet — used to HOLD the last
    // shown value instead of snapping to parity while the analyzer catches up to a new move.
    private struct ShownEval: Equatable { let fraction: Double; let text: String }
    private var currentEval: ShownEval? {
        if let e = liveEval {
            let pawns = Double(e.cp) / 100
            let sign = pawns > 0 ? "+" : (pawns < 0 ? "\u{2212}" : "")
            return ShownEval(fraction: min(1, max(0, e.winPct / 100)), text: sign + String(format: "%.1f", abs(pawns)))
        }
        // Coach-painted eval — only trust it for the LIVE board (not while browsing history).
        if displayedFen == board?.fen, board?.eval != nil {
            return ShownEval(fraction: EvalPresentation.fraction(board), text: EvalPresentation.text(board))
        }
        return nil
    }
    // Move to the newest eval; if there isn't one yet, keep the previous (no drop to 0).
    private func updateShownEval(animated: Bool) {
        guard let e = currentEval else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) { shownEvalFraction = e.fraction }
        } else {
            shownEvalFraction = e.fraction
        }
        shownEvalText = e.text
    }
    private var highlights: [Highlight] { board?.highlights ?? [] }
    private var arrows: [Arrow] { board?.arrows ?? [] }
    private var beats: [Beat] { stream?.beats ?? [] }

    // The rail's sessions in a STABLE order: the server sorts by recency and re-pushes when you resume
    // one (bumping it to the top), which would yank the clicked row under the cursor. So we lock the
    // order at first load and keep it; new sessions arriving later slot in via `sessionOrder`.
    private var orderedSessions: [SessionInfo] {
        let live = stream?.sessions ?? []
        let byId = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = sessionOrder.compactMap { byId[$0] }          // known ids, frozen order
        let known = Set(sessionOrder)
        for s in live where !known.contains(s.id) { result.append(s) }  // not-yet-ordered ones
        return result
    }

    // This drill hides a human trap — from the deterministic build-time flag, or the coach's live check.
    private var positionHasPoisonedLine: Bool { stream?.drill?.hasPoisonedLine == true || board?.hasPoisonedLine == true }
    // It's the player's turn to solve in the active drill (the moment to warn).
    private var isPlayerTurnInDrill: Bool {
        guard let solve = stream?.drill?.sideToSolve, let side = board?.sideToMove else { return false }
        return solve.hasPrefix(side)
    }

    var body: some View { applyDrillHandlers(rootView) }

    /// The drill/poisoned-line stream observers, split out of `rootView` so the main modifier chain
    /// stays short enough for the Swift type-checker (onChange order is irrelevant — these are
    /// independent observers).
    private func applyDrillHandlers(_ content: some View) -> some View {
        content
            .onChange(of: stream?.drill?.seq) { _, _ in resetForNewDrill() }
            // Latch "this drill had a trap" — from the deterministic drill flag or the coach's board flag.
            .onChange(of: stream?.drill?.hasPoisonedLine) { _, has in if has == true { hadPoisonedLine = true } }
            .onChange(of: stream?.board?.hasPoisonedLine) { _, has in if has == true { hadPoisonedLine = true } }
            // Latch the poisoned LINE (+ where it branches from) while it's on the board — it clears on
            // the next repaint, so we capture it now to show as a variation on reveal.
            .onChange(of: stream?.board?.poisonedLine) { _, pl in latchPoisonedLine(pl) }
            // A session reset (board cleared) resets sticky orientation + retry/poisoned-line state.
            .onChange(of: stream?.board == nil) { _, gone in if gone { resetOnBoardCleared() } }
    }

    private var rootView: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                ModeRailView(selected: mode, sessions: orderedSessions,
                             currentSession: session, onNewSession: startNewSession,
                             onResumeSession: resume, loading: isWarmingUp) { mode = $0 }
                content
            }
            if settingsOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { settingsOpen = false }
                // Drop from the rail-foot gear now: bottom-left, just right of the rail.
                SettingsMenu(flipped: $flipped, engineOn: $engineOn) { settingsOpen = false }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, Theme.Size.rail + Theme.Spacing.sm)
                    .padding(.bottom, Theme.Size.contentPadBottom + 24)
            }
        }
        // The variation menu — a custom card (not a system popover) floated right above the tapped
        // caret via its reported anchor. The card floats in a non-blocking overlay (empty area passes
        // clicks through), so a click OUTSIDE dismisses AND performs its action in one go — driven by a
        // mouse-down monitor that never consumes the event, guarded by hover so clicking a row still works.
        .overlayPreferenceValue(CaretAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let oc = openCaret, let anchor = anchors[oc.id] {
                    let rect = proxy[anchor]
                    VariationMenu(nodes: oc.nodes, backLabel: oc.backLabel,
                                  isWrong: { isWrongTry(branchFen: oc.branchFen, $0) },
                                  onPick: { node in enterVariation(at: oc.index - 1, node: node); openCaret = nil },
                                  onBack: { switchToParent() })
                    .fixedSize()
                    .onHover { hoveringPopover = $0 }
                    .frame(width: proxy.size.width, height: max(rect.minY - 6, 0), alignment: .bottomLeading)
                    .offset(x: rect.minX)
                }
            }
        }
        .background(GlobalMouseDownDismiss(active: openCaret != nil) {
            if !hoveringPopover { openCaret = nil }   // a click off the card dismisses it (click still acts)
        })
        .background(Theme.windowBackground.ignoresSafeArea())
        // Resolve the durable session id before the terminal mounts. The rail's session list arrives
        // live on the /state stream (server pushes it) — no polling.
        .task {
            if session == nil { session = await resolveSession() }
            // Don't clobber the server's resumed board with our default before the snapshot lands:
            // at launch `stream.board` is nil so displayedFen is the start FEN, and posting it would
            // overwrite a persisted/resumed position. The onChange(displayedFen) sync (gated on
            // `ready`) reports the position once a real board has arrived over /state.
            if stream?.ready == true { await coach?.setBoardPosition(displayedFen) }
        }
        // A new position snaps the navigator back to live. The wrong-move hold is deliberately NOT
        // touched here — the coach coaching a wrong move repaints the board (often the refutation,
        // a different FEN), and that must not dismiss the hold. The hold is owned by the move result
        // (kept on wrong, cleared on correct in playMove) and by Retry; a new drill clears a stale one.
        // A new live board snaps the navigator to live — but only if we're not off exploring a
        // variation (a coach repaint shouldn't yank you out of a "what if"). Inside a variation, the
        // server is still authoritative: if it snapped the board back to the node before our cursor
        // (an undo), FOLLOW it — drop the wrong tip move and step back.
        .onChange(of: stream?.board?.fen) { _, fen in
            // The live board just landed — drop the optimistic hold now (not on the /move response,
            // which can beat the board event and flicker back to the old position). A WRONG drill move
            // doesn't advance the board, so this never fires for it; its hold stays until Retry.
            let heldFen = heldWrong
            heldWrong = nil
            guard varStack.isEmpty else { if let fen { followServerUndo(fen) }; return }
            // If the live board advanced PAST the player's optimistic move, the opponent (the drill bot)
            // just replied — SLIDE that reply in instead of popping it. Anchor on the player-move ply
            // first (same position as the hold, so no visible jump, but now ON the line with stable
            // piece ids), then animate one step to the live tip so the opponent's piece slides. Use the
            // LAST matching ply (rook-dance puzzles repeat positions). Falls back to an instant snap if
            // the plies don't line up — never worse than before.
            if let heldFen, let fen,
               VariationForest.norm(fen) != VariationForest.norm(heldFen),
               let k = history.lastIndex(where: { VariationForest.norm($0.fen) == VariationForest.norm(heldFen) }),
               k + 1 < history.count {
                viewIndex = k
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) { viewIndex = nil }   // the bot's reply slides
                }
            } else {
                viewIndex = nil
            }
        }
        // Stable piece ids for the move line; recomputed on appear and whenever the line changes.
        .task(id: history) { pieceIdMaps = PieceTrack.idMaps(history) }
        // Capture the solver's side once per drill; keep it after the drill ends (stable orientation).
        .onChange(of: stream?.drill?.sideToSolve) { _, s in if let s { drillBottomBlack = (s == "black") } }
        // Live analysis follows the Analysis tab, the toggle, and the position shown (debounced).
        .onChange(of: rightTab) { _, _ in syncAnalysis() }
        .onChange(of: analysisOn) { _, _ in syncAnalysis() }
        .onChange(of: engineOn) { _, _ in syncAnalysis() }
        // Analysis follows the position, AND we report the FULL view to the server (the resolved line,
        // the variation forest, the cursor) so the backend mirrors exactly what the user sees and can
        // replay it on resume. Gated on `ready`: during the initial snapshot the server is replaying a
        // resumed view TO us, so we must not push an (empty) view back and clobber it — we emit only
        // after the snapshot has landed (see hydrateView).
        .onChange(of: displayedFen) { _, _ in
            syncAnalysis()
            guard stream?.ready == true else { return }
            let snap = viewSnapshot()
            let fen = displayedFen
            Task {
                // Keep BOTH surfaces on the shown board: `/position` feeds read_input's `board_fen`
                // (the coach's "this position"), `/view` feeds get_view. Before this, only the view was
                // reported on navigation, so `board_fen` went stale the moment you stepped into a
                // variation — the coach then grounded "what do you think here?" on the mainline board.
                await coach?.setBoardPosition(fen)
                await coach?.setView(snap)
            }
        }
        // Resume: the server replayed the persisted view (once, in the initial snapshot) — rebuild the
        // exact tree + cursor the user left. viewEpoch bumps only on a `view` event (connect/switch).
        .onChange(of: stream?.viewEpoch) { _, _ in if let v = stream?.view { hydrateView(v) } }
        // Flipping the board doesn't change `displayedFen`, so the view sync above never fires for
        // it — but orientation IS "I"/"me" server-side (CoachPrompt.frame), so a flip has to reach
        // the backend on its own.
        .onChange(of: povColor) { _, _ in
            guard stream?.ready == true else { return }
            Task { await coach?.setView(viewSnapshot()) }
        }
        // Eval bar: animate from the PREVIOUS value to the new one as the analyzer (or a coach paint)
        // produces it; hold the old value in between so a move never dips the bar to parity. Watch the
        // single DERIVED eval, not its two raw sources (engineLines + board.eval) — a fresh snapshot can
        // change both in one frame, and two onChanges firing would mutate the eval twice per frame
        // (SwiftUI: "tried to update multiple times per frame"). currentEval coalesces them, so this
        // fires at most once per frame.
        .onChange(of: currentEval) { _, _ in updateShownEval(animated: true) }
        .task { updateShownEval(animated: false) }
        // Lock the rail order: on first load take the server's recency sort; afterwards only add newly
        // created sessions (at the top) and drop deleted ones — never re-sort on resume.
        .onChange(of: (stream?.sessions ?? []).map(\.id)) { _, ids in
            let known = Set(sessionOrder)
            sessionOrder = ids.filter { !known.contains($0) } + sessionOrder   // new on top, rest frozen
            sessionOrder.removeAll { !ids.contains($0) }                       // drop deleted
        }
        // Silent-turn safety net: mark the beat count when the coach starts, and if it stops without
        // having pushed a single beat, post an app-authored nudge (no terminal scraping — that would
        // leak the coach's private reasoning / spoilers). Points the player at the terminal for detail.
        .onChange(of: coachWorking) { _, working in
            if working {
                beatsAtWorkStart = beats.count
                activityAtWorkStart = stream?.activeIdx ?? 0
            } else if beats.count == beatsAtWorkStart && expectCoachBeat
                        && (stream?.activeIdx ?? 0) == activityAtWorkStart {
                // …but NOT if the turn switched activities (e.g. a pasted position that IS a puzzle →
                // enters the puzzle surface and presents there). The beat landed in the new frame, so a
                // same-frame count comparison reads a false "silent turn". A frame switch is never silent.
                stream?.pushLocalBeat("Uh oh, I didn't catch that. Please check the box below for more details.")
            }
        }
    }

    /// Tell the server whether to run live analysis and on which position — debounced, so arrowing
    /// through moves doesn't spam it. Runs only while the Analysis tab is open and the toggle is on.
    private func syncAnalysis() {
        // Run the dedicated analyzer whenever the engine is on and a real position is up — the eval bar
        // reads its live eval, so it fills in immediately (not only when the Analysis tab is open).
        let active = engineOn && board != nil
        let fen = displayedFen
        analyzeTask?.cancel()
        analyzeTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await coach?.setAnalysis(on: active, fen: fen)
        }
    }

    /// Start a fresh coaching session: the BACKEND mints the id (and switches to it, pushing a clean
    /// snapshot over the WS); we adopt what it returns. Falls back to a local id if the server is down.
    private func startNewSession() {
        conversationStarted = false   // a fresh session shows the starter tips again
        Task {
            switch await coach?.newSession() {
            case .id(let id):
                coach?.openChat(id)   // move THIS socket to it, or the clean slate lands only on reconnect
                session = id
            case .rejected:
                // The token is dead and the login is taking over. Do NOTHING: minting a local id here
                // would build a session the server never heard of and push it up a socket that is
                // being torn down — strictly worse than the empty state the user is about to see.
                break
            case .failed, .none:
                // The server is down, which is not an auth problem. A local id keeps the user moving.
                let id = freshSession()
                coach?.openChat(id)
                session = id
            }
        }
    }

    /// Resume an existing session from the rail — same swap, with its id (claude --resume picks it up).
    private func resume(_ id: String) { conversationStarted = false; swap(to: id) }

    private func swap(to id: String) {
        Task {
            await coach?.setSessionId(id)   // server records the session first (so /sessions has it)
            coach?.openChat(id)             // ...then move THIS socket to it (see openChat)
            session = id                     // then swap → refetch the rail list + remount terminal
        }
    }

    /// The durable session id to resume. The server is spawned in parallel and takes a few seconds
    /// to listen, so we retry until it answers — it always returns the persisted (latest) session id,
    /// so a successful fetch is the right one to resume. Only mint a fresh id if it never comes up
    /// (otherwise every launch would start afresh on a transient startup miss).
    private func resolveSession() async -> String {
        for _ in 0 ..< 60 {                                  // ~30s of half-second retries
            if let id = await coach?.currentSessionId() { return id }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return freshSession()
    }

    private func freshSession() -> String { UUID().uuidString.lowercased() }

    /// We're viewing a saved/live ACTIVITY (a puzzle), not the base conversation. Drives the distinct
    /// coach pane (the board + rail never change): entering an activity transitions the COACH PANE to
    /// the puzzle's conversation, leaving returns it to the session's.
    private var inActivity: Bool { (stream?.activeIdx ?? 0) > 0 }

    private var content: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                    boardColumn(height: geo.size.height)          // board — SAME in session and puzzle
                    beatsColumn(columnHeight: geo.size.height)    // coach pane — this is what transitions
                }
            }
            .padding(.top, Theme.Size.bodyTopGap)
        }
        .padding(.top, Theme.Size.contentPadTop)
        .padding(.horizontal, Theme.Size.contentPadH)
        .padding(.bottom, Theme.Size.contentPadBottom + 24)   // lift the board + terminal off the floor
    }

    /// The board fills the available column height (square, up to `boardMax`), bottom-aligned so
    /// its lower edge meets the terminal at the foot of the beats column.
    private func boardColumn(height: CGFloat) -> some View {
        let barW = Theme.Size.evalBar.height          // the bar's thickness → its width, now vertical
        // Reserve room below the board for the navigator box + a gap AND the gear that hangs under the
        // eval bar, so the board shrinks to fit instead of shoving the navigator past the column foot.
        let navReserve: CGFloat = 80
        let boardSize = max(Theme.Size.boardMin,
                            min(height - Theme.Size.boardReserve - navReserve, Theme.Size.boardMax))
        // SessionBoardView pads its size×size squares by boardFramePad on every side, so its OUTER
        // frame is taller/wider than `boardSize` — match the bar to that, not the bare size.
        let boardOuter = boardSize + 2 * Theme.Size.boardFramePad
        let totalW = barW + Theme.Spacing.sm + boardOuter
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(spacing: Theme.Spacing.sm) {          // eval bar, with the settings gear beneath it
                    EvalBarView(fraction: shownEvalFraction)   // vertical — live server eval
                        .frame(width: barW, height: boardOuter)
                        .shadow(color: Theme.Palette.ink.opacity(0.5), radius: 18, x: 0, y: 10)  // match board lift
                    Button { settingsOpen.toggle() } label: {
                        Image(systemName: Theme.Symbol.gear)
                            .foregroundStyle(settingsOpen ? Theme.Palette.ink : Theme.Palette.ink55)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .frame(width: barW)
                }
                SessionBoardView(
                    fen: displayedFen, highlights: highlights, arrows: arrows, flipped: boardFlipped,
                    size: boardSize,
                    // Interactive only on a real, live position — never on the placeholder start board
                    // (a drag there would post a stray move), nor while browsing history / holding a
                    // wrong move (that resolves via Retry).
                    // Live at the mainline tip → a drill answer (playMove). Browsing history or inside a
                    // variation → a "what if" variation move (playVariation, local). Placeholder board, a
                    // held wrong move, OR the OPPONENT's turn in a puzzle (their replies are the fixed
                    // line — read-only; you only ever move as the solver) → locked.
                    onMove: (board == nil || heldWrong != nil || opponentToMoveInPuzzle) ? nil
                        : drillMoveInVariation ? playDrillVariation
                        : (isViewingHistory || isInVariation) ? playVariation : playMove,
                    pieceIds: currentPieceIds   // stable ids while viewing the line → steps slide, don't remap
                )
                .overlay {
                    // While the coach is working, an AI energy-line travels around the board.
                    if coachWorking { CoachThinkingHalo() }
                }
                .overlay { if pendingPromotion != nil { promotionPicker } }   // pick Q/R/B/N
                .animation(.easeInOut(duration: 0.35), value: coachWorking)
            }
            .frame(width: totalW, alignment: .leading)
            .overlay(alignment: .topTrailing) {          // just the eval readout, floated above the board
                Text(shownEvalText)
                    .font(Theme.Typography.evalReadout)
                    .foregroundStyle(Theme.Palette.ink82)
                    .contentTransition(.numericText())    // roll the digits, don't cut
                    .offset(y: -(evalGearRowH + Theme.Spacing.xs))
            }
            Spacer(minLength: Theme.Spacing.md)   // guaranteed gap between board and the navigator
            if let board {                        // "BLACK TO MOVE" / "YOUR MOVE" — sits just above the navigator
                Text(turnLabel(board))
                    .font(Theme.Typography.label)
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.ink45)
                    .frame(width: boardOuter, alignment: .leading)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            // The navigator is the column's last element, so its bottom edge lands at the column foot
            // (= the terminal's bottom). navReserve keeps it there even with the gear under the bar.
            MoveNavigatorView(
                line: navigatorLine, cursor: lineCursor, inVariation: isInVariation,
                // The "?" placeholder always "has variations" — its wrong tries. (Same gold underline.)
                hasVariations: { $0 == placeholderIndex ? true : hasAlternatives($0) },
                onSelect: { i in
                    // Jump the board to a move in the shown line. Not wrapped in withAnimation → a random
                    // jump snaps (no multi-piece slide). On the mainline, the last move can go "live".
                    if i == placeholderIndex {                     // "?" → show the solving position (live tip)
                        if isInVariation { varCursor = displayLine.count - 1 } else { viewIndex = nil }
                    }
                    else if isInVariation { varCursor = i }
                    else {
                        viewIndex = (i >= liveIndex && history.indices.contains(i)
                                     && history[i].fen == board?.fen) ? nil : i
                    }
                },
                onCaretTap: { id, idx in
                    if idx == placeholderIndex {
                        // The "?" caret lists every wrong try parked at the solving position.
                        openCaret = (openCaret?.id == id) ? nil
                            : OpenCaret(id: id, index: idx, nodes: variations.at(solvingFen ?? ""),
                                        branchFen: solvingFen ?? "")
                    } else {
                        openCaret = (openCaret?.id == id) ? nil : makeOpenCaret(id: id, lineIndex: idx)
                    }
                },
                onBack: variationBack,
                onCancel: variationCancel
            )
            // Live move-list changes (a played move, or a drill backtrack rewriting history) must NOT
            // animate — the move-group `.transition` was flashing every ply in/out. Null the animation
            // for `history`-driven changes; variation nav still animates (it drives varCursor/varStack
            // under explicit withAnimation, not history).
            .animation(nil, value: history)
            .frame(width: boardOuter)                            // navigator spans the board, not the bar
            .background(isInVariation ? Theme.Palette.boardDark : Theme.Palette.paper)   // dark = side-line
            .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))   // boxed, like the terminal
            .shadow(color: Theme.Palette.ink.opacity(0.5), radius: 18, x: 0, y: 10)  // match board lift
            .frame(width: totalW, alignment: .trailing)          // aligned under the board (right of the bar)
        }
        // Arrow keys step the move navigator; focus the board so they reach us (not the terminal).
        // `focusEffectDisabled` keeps the focus (for the keys) but drops the macOS blue focus ring.
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        .onAppear { boardFocused = true }
        .onKeyPress(.leftArrow) { stepBack(); return .handled }
        .onKeyPress(.rightArrow) { stepForward(); return .handled }
    }

    /// The stable-id map for the position currently shown, so steps slide the right piece. On the
    /// mainline it's the precomputed per-ply map; inside a variation we CONTINUE that map through the
    /// variation's moves (same piece-tracking), so a slide into/along a variation stays clean too. nil
    /// off any known line (a held wrong move, a Retry solve fen, a diverged live board) → snap.
    private var currentPieceIds: [String: String]? {
        let line = displayLine
        let i = lineCursor
        guard line.indices.contains(i), line[i].fen == displayedFen else { return nil }
        if !isInVariation {                                 // pure mainline → use the precomputed map
            guard pieceIdMaps.indices.contains(i) else { return nil }
            return pieceIdMaps[i]
        }
        // In a variation: walk stable ids from the start of the shown line up to the cursor.
        var counter = 0
        func fresh() -> String { defer { counter += 1 }; return "pc\(counter)" }
        var map: [String: String] = [:]
        for sq in PieceTrack.squares(line[0].fen).sorted() { map[sq] = fresh() }
        var prev = line[0].fen
        for k in 1...max(1, i) where k <= i {
            map = PieceTrack.advance(map, prevFen: prev, curFen: line[k].fen, uci: line[k].uci, mint: fresh)
            prev = line[k].fen
        }
        return map
    }

    /// Step one ply back — within the shown line (mainline or variation). The moved piece keeps its
    /// STABLE id across the two positions, so the `withAnimation` fen change slides it, at any speed.
    private func stepBack() {
        if isInVariation {
            guard varCursor > 0 else { return }
            withAnimation(.easeInOut(duration: 0.28)) { varCursor -= 1 }
            revealVariationsAtCursor()
            return
        }
        guard !history.isEmpty else { return }
        let cur = viewIndex ?? liveIndex
        guard cur > 0 else { return }
        withAnimation(.easeInOut(duration: 0.28)) { viewIndex = cur - 1 }
        revealVariationsAtCursor()
    }

    /// Step one ply forward — within the shown line; on the mainline, reaching the tip resumes live.
    private func stepForward() {
        if isInVariation {
            guard varCursor < displayLine.count - 1 else { return }
            withAnimation(.easeInOut(duration: 0.28)) { varCursor += 1 }
            revealVariationsAtCursor()
            return
        }
        guard let cur = viewIndex else { return }
        let next = cur + 1
        withAnimation(.easeInOut(duration: 0.28)) { viewIndex = next >= liveIndex ? nil : next }
        revealVariationsAtCursor()
    }

    /// Keyboard nav lands on a move → show its variation menu (or dismiss any open one if it has none).
    private func revealVariationsAtCursor() {
        let l = displayLine
        let i = lineCursor
        openCaret = l.indices.contains(i) ? makeOpenCaret(id: l[i].id, lineIndex: i) : nil
    }

    /// The mainline ply index whose position equals `fen` (normalized), or nil if `fen` isn't on the
    /// mainline. Used so a move that matches the mainline resolves to it instead of duplicating it.
    private func mainlinePlyIndex(forFen fen: String) -> Int? {
        let n = VariationForest.norm(fen)
        return history.firstIndex { VariationForest.norm($0.fen) == n }
    }
    /// The mainline's continuation UCI from `fen` (nil at the tip / off the mainline).
    private func mainlineNextUci(forFen fen: String) -> String? {
        guard let k = mainlinePlyIndex(forFen: fen), history.indices.contains(k + 1) else { return nil }
        return history[k + 1].uci
    }
    /// The moves that could be played INSTEAD of the move at line index `i` — i.e. the other
    /// continuations from the position BEFORE it. `nodes` are the other sidelines from that position
    /// (each its own line); `backLabel` is the parent line M branched away from, present only when M is
    /// itself a variation's first move (so you can switch back to what it replaced). nil = no alternatives.
    private func alternativesInfo(_ i: Int) -> (nodes: [VarNode], backLabel: String?)? {
        let l = displayLine
        guard i >= 1, l.indices.contains(i) else { return nil }
        let m = l[i]
        let before = l[i - 1].fen                                   // the position M was played from
        let nodes = variations.at(before).filter { $0.uci != m.uci }   // the OTHER sidelines from here
        var backLabel: String? = nil
        if let si = varStack.firstIndex(where: { $0.branchLineIndex == i - 1 }) {   // M is a variation's first move
            let parent = buildLine(Array(varStack.prefix(si)))     // the line M branched away from
            if parent.indices.contains(i) {
                backLabel = MoveListStyle.numberedLine(Array(parent[i...]))   // its move here + the rest
            } else if parent.indices.contains(i - 1), let s = parent[i - 1].san {
                backLabel = MoveListStyle.figurine(s)
            } else {
                backLabel = "…"
            }
        }
        guard backLabel != nil || !nodes.isEmpty else { return nil }
        return (nodes, backLabel)
    }
    private func hasAlternatives(_ i: Int) -> Bool { alternativesInfo(i) != nil }
    private func makeOpenCaret(id: String, lineIndex i: Int) -> OpenCaret? {
        guard let info = alternativesInfo(i) else { return nil }
        let before = displayLine.indices.contains(i - 1) ? displayLine[i - 1].fen : ""
        return OpenCaret(id: id, index: i, nodes: info.nodes, backLabel: info.backLabel, branchFen: before)
    }

    /// "← parent" from the popover — switch to the line M branched away from, landing on its move here.
    private func switchToParent() {
        guard let oc = openCaret, let si = varStack.firstIndex(where: { $0.branchLineIndex == oc.index - 1 }) else { return }
        let seg = varStack[si]
        openCaret = nil
        let target = seg.branchLineIndex + 1       // the parent's move at this branch (== oc.index)
        varStack = Array(varStack.prefix(si))      // drop this segment AND everything nested above it
        if varStack.isEmpty {
            viewIndex = target >= liveIndex ? nil : target
        } else {
            varCursor = min(target, max(0, buildLine(varStack).count - 1))
        }
    }

    /// Play a move while browsing the line → branch (or extend) a VARIATION, entirely locally. Never
    /// goes through the drill adjudicator — this is exploration, not a drill answer. The engine still
    /// grounds its eval (the analyzer follows `displayedFen`).
    private func playVariation(_ from: String, _ to: String) {
        let fen = displayedFen
        guard ChessMove.isLegal(fen, from: from, to: to),
              let applied = ChessMove.apply(fen, from: from, to: to) else { return }
        let line = displayLine
        let i = lineCursor
        // Replaying the move that already continues this line → just step forward.
        if line.indices.contains(i + 1), line[i + 1].uci == applied.uci {
            if isInVariation { withAnimation(.easeInOut(duration: 0.28)) { varCursor = i + 1 } }
            else { withAnimation(.easeInOut(duration: 0.28)) { viewIndex = i + 1 >= liveIndex ? nil : i + 1 } }
            return
        }
        // The move IS the mainline's own continuation from here → go to the MAINLINE, never branch a
        // duplicate of it. (This is the bug: from a branch point inside a variation, playing the
        // mainline move used to create a sideline identical to the mainline.)
        if let k = mainlinePlyIndex(forFen: fen), history.indices.contains(k + 1),
           history[k + 1].uci == applied.uci {
            let target = k + 1
            varStack = []; varCursor = 0; openCaret = nil
            withAnimation(.easeInOut(duration: 0.28)) { viewIndex = target >= liveIndex ? nil : target }
            return
        }
        let san = ChessMove.san(fen, from: from, to: to)
        let node = VarNode(uci: applied.uci, san: san, fen: applied.fen)
        // At the tip of an existing variation segment → EXTEND it. Otherwise BRANCH a new segment.
        // Inserting a move SNAPS (no animation) — the strip's collapse/emerge animation is Back-only.
        if isInVariation, i == line.count - 1, !varStack.isEmpty {
            varStack[varStack.count - 1].nodes.last?.next = node
            varStack[varStack.count - 1].nodes.append(node)
            varCursor = i + 1
        } else {
            let attached = variations.add(node, from: fen)     // dedup: re-enters an existing sibling
            varStack.append(VarSegment(branchLineIndex: i, nodes: attached.line))
            varCursor = i + 1
        }
    }

    /// Enter the variation containing `node` (from a caret popover). The caret lists moves played
    /// INSTEAD of M, so `lineIndex` is the branch point BEFORE M (`oc.index - 1`): the sideline
    /// REPLACES M, landing on it in M's own slot. Snaps — the animation is Back-only.
    private func enterVariation(at lineIndex: Int, node: VarNode) {
        // Switching to a sibling at the SAME branch replaces the current variation rather than stacking.
        if varStack.last?.branchLineIndex == lineIndex { varStack.removeLast() }
        varStack.append(VarSegment(branchLineIndex: lineIndex, nodes: node.line))
        varCursor = lineIndex + 1
    }

    /// Follow a server-authoritative UNDO while inside a variation. `undo_move` snaps the session board
    /// back to the node just before the viewed move; the app is only an origin, so it obeys: drop the
    /// wrong tip move from the current sideline and step the cursor back. Narrowly gated — it fires ONLY
    /// when the incoming board is exactly the previous node's fen and the viewed move is a variation node,
    /// so an ordinary coach repaint (a different fen) never yanks the player out of their "what if".
    private func followServerUndo(_ fen: String) {
        guard isInVariation, varCursor > 0, !varStack.isEmpty else { return }
        let line = displayLine
        guard line.indices.contains(varCursor - 1), line[varCursor - 1].fen == fen,
              line.indices.contains(varCursor), line[varCursor].node != nil else { return }
        var seg = varStack[varStack.count - 1]
        guard !seg.nodes.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.24)) {
            seg.nodes.removeLast()
            seg.nodes.last?.next = nil                 // keep the linked list consistent with the array
            if seg.nodes.isEmpty { varStack.removeLast() }   // sideline emptied → back on the parent line
            else { varStack[varStack.count - 1] = seg }
            varCursor -= 1
        }
    }

    /// Back — pop one variation level, in two quick sequential parts: (1) this variation's moves
    /// collapse left into the branch, then (2) the parent line's continuation slides in from the right.
    private func variationBack() {
        guard let seg = varStack.last else { return }
        openCaret = nil
        // Phase 1 — truncate to the branch so this variation's moves leave (removal → left).
        withAnimation(.easeIn(duration: 0.14)) {
            collapseTo = seg.branchLineIndex
            varCursor = seg.branchLineIndex
        }
        // Phase 2 — pop, releasing the parent continuation to slide in (insertion → right).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.18)) {
                varStack.removeLast()
                if varStack.isEmpty {
                    viewIndex = seg.branchLineIndex >= liveIndex ? nil : seg.branchLineIndex
                    solvingSiblingBranch = false   // back on the mainline → drill over
                }
                collapseTo = nil
            }
        }
    }

    /// Cancel — drop all variations and SNAP straight to the mainline (no animation).
    private func variationCancel() {
        let mainIdx = varStack.first?.branchLineIndex
        varStack = []; varCursor = 0; collapseTo = nil; openCaret = nil
        solvingSiblingBranch = false   // leaving the sibling drill
        if let m = mainIdx { viewIndex = m >= liveIndex ? nil : m }
    }

    /// Tapping a played-move chip in the chat: snap the board to the position after that move by moving
    /// the navigator cursor to its ply. Reuses the mainline cursor, so it clears cleanly on a new move.
    /// A move not in the line (e.g. a wrong drill move, which isn't recorded) is a no-op.
    private func snapToMove(_ fen: String) {
        let key = VariationForest.norm(fen)
        guard let i = history.firstIndex(where: { VariationForest.norm($0.fen) == key }) else { return }
        clearVariationCursor()
        heldWrong = nil
        viewIndex = (i >= liveIndex && history.indices.contains(i) && history[i].fen == board?.fen) ? nil : i
    }

    /// Drop out of any variation (used when the drill/board resets under us).
    private func clearVariationCursor() {
        varStack = []; varCursor = 0; collapseTo = nil; openCaret = nil
        solvingSiblingBranch = false
    }

    /// A fresh drill: reset retry/poisoned-line state and drop the old line's variations.
    private func resetForNewDrill() {
        heldWrong = nil; solveFen = nil; lastMoveWrong = false; continueBranchPending = false
        walker = stream?.drill.map(DrillWalker.init)   // fresh local walk from the new tree's root
        // Own the move line for a local drill: seed from the server's line (the restored line on a reopen,
        // or [root] on a fresh puzzle); if that hasn't landed yet, fall back to the tree's root so the line
        // is NEVER empty (an empty line blanked the board before). No walker → hand it back to the server.
        if let d = stream?.drill {
            let srv = stream?.history ?? []
            localLine = srv.isEmpty ? [Ply(n: 0, san: nil, uci: nil, fen: d.fen)] : srv
            var map: [String: Set<String>] = [:]           // the tree's accepted moves per position
            Self.collectSolutionMoves(d.root, into: &map)
            solutionUci = map
        } else {
            localLine = nil
            solutionUci = [:]
        }
        // Seed "this drill has a trap" from the NEW drill's current flag, do NOT just zero it: the
        // onChange(hasPoisonedLine) latch only fires on a VALUE change, so re-arming the SAME poisoned
        // position (true→true) would never re-latch, and the post-solve "show me the trap" nudge would
        // silently vanish on a restart. (The board flag is durable now, so it can't rescue this either.)
        hadPoisonedLine = positionHasPoisonedLine
        poisonedLineNudge = false; baseConceptClosed = false
        latchedPoisonedLine = nil; latchedPoisonedFrom = nil   // the poisoned line belongs to the old drill
        variations.removeAll(); clearVariationCursor()
    }

    /// Walk the solution tree, recording the accepted student move(s) at each solving position (keyed by
    /// normalized fen). Solve nodes accept one move; mate nodes accept any listed mating move.
    private static func collectSolutionMoves(_ node: PuzzleNode, into map: inout [String: Set<String>]) {
        switch node.kind {
        case "solve":
            if let fen = node.fen, let uci = node.expectUci { map[VariationForest.norm(fen), default: []].insert(uci) }
            if let after = node.after { collectSolutionMoves(after, into: &map) }
        case "mate":
            if let fen = node.fen {
                for o in node.options ?? [] { map[VariationForest.norm(fen), default: []].insert(o.uci) }
            }
            for o in node.options ?? [] { collectSolutionMoves(o.then, into: &map) }
        case "reply":
            for d in node.defenses ?? [] { collectSolutionMoves(d.then, into: &map) }
        default:
            break
        }
    }

    /// A variation node is a WRONG try when it branches from a KNOWN solving position and its move isn't
    /// one the tree accepts there. Derived from the tree, so it needs no persisted flag and is correct
    /// again the moment the puzzle reopens. A branch off a non-solving spot (an opponent reply, an
    /// explored line) has no accepted-move entry → never marked wrong.
    private func isWrongTry(branchFen: String, _ node: VarNode) -> Bool {
        guard let accepted = solutionUci[VariationForest.norm(branchFen)] else { return false }
        // Tolerate a promotion-suffix mismatch (e2e8 vs e2e8q) — prefix-match either direction.
        return !accepted.contains { $0 == node.uci || node.uci.hasPrefix($0) || $0.hasPrefix(node.uci) }
    }

    /// Capture the poisoned line while it's on the board (it clears on the next repaint).
    private func latchPoisonedLine(_ pl: [BoardState.PoisonedMove]?) {
        if let pl, !pl.isEmpty, let from = stream?.board?.fen {
            latchedPoisonedLine = pl; latchedPoisonedFrom = from
        }
    }

    /// The board was cleared (session reset): drop sticky orientation + retry/poisoned-line state.
    private func resetOnBoardCleared() {
        drillBottomBlack = nil; solveFen = nil; heldWrong = nil; lastMoveWrong = false; walker = nil; continueBranchPending = false
        hadPoisonedLine = false; poisonedLineNudge = false; baseConceptClosed = false
        latchedPoisonedLine = nil; latchedPoisonedFrom = nil
        variations.removeAll(); clearVariationCursor()
    }

    /// "Show me the poisoned line": load the latched trap line as a LOCAL variation branching off the
    /// position it was played from, then animate its first move in from that position. Returns false if
    /// there's no captured line or it can't be placed on the mainline (caller falls back to the server).
    @discardableResult
    private func showPoisonedLineVariation() -> Bool {
        // Prefer the DRILL's line (computed at build, persists through solve); fall back to a line
        // latched off a coach board-analysis. Each carries the position it branches from.
        let source: (moves: [BoardState.PoisonedMove], from: String)? = {
            if let d = stream?.drill, let m = d.poisonedLineMoves, !m.isEmpty { return (m, d.fen) }
            if let m = latchedPoisonedLine, !m.isEmpty, let f = latchedPoisonedFrom { return (m, f) }
            return nil
        }()
        guard let (pl, from) = source else { return false }
        let key = VariationForest.norm(from)
        guard let branchPly = history.firstIndex(where: { VariationForest.norm($0.fen) == key }) else { return false }
        // Build the poisoned line as a linked VarNode chain and register it off the trap position.
        let nodes = pl.map { VarNode(uci: $0.uci, san: $0.san, fen: $0.fen) }
        for k in 0 ..< max(0, nodes.count - 1) { nodes[k].next = nodes[k + 1] }
        guard let head = nodes.first else { return false }
        let attached = variations.add(head, from: from)
        let seg = VarSegment(branchLineIndex: branchPly, nodes: attached.line)
        // Phase 1 — snap to the branch position (the "previous position in the line"), no animation.
        clearVariationCursor()
        viewIndex = branchPly
        // Phase 2 — next runloop, slide the first poisoned move in from that position. The variation's
        // shared prefix carries the same piece ids as the mainline, so the moved piece animates.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.32)) {
                varStack = [seg]
                varCursor = branchPly + 1
            }
        }
        return true
    }

    // -- backend view mirroring (contract M-session-view) -----------------
    /// The wire snapshot of what's on screen right now — the resolved line, the whole variation
    /// forest, and the cursor — for `POST /view`. Snake_case keys: the server reads them verbatim.
    private func viewSnapshot() -> [String: Any] {
        let l = displayLine
        let lineWire: [[String: Any]] = l.enumerated().map { i, m in
            var d: [String: Any] = ["i": i, "fen": m.fen, "branch": m.isBranch,
                                    "kind": m.node == nil ? "main" : "variation"]
            if let san = m.san { d["san"] = san }
            if let uci = m.uci { d["uci"] = uci }
            return d
        }
        // Map a branch's normalized key back to a full fen + mainline ply (if it sits on the mainline),
        // so the coach can label the branch and the mainline prefix round-trips against `history`.
        var full: [String: (String, Int?)] = [:]
        for (n, p) in history.enumerated() { full[VariationForest.norm(p.fen)] = (p.fen, n) }
        for (_, nodes) in variations.branches { for head in nodes { for node in head.line {
            let k = VariationForest.norm(node.fen); if full[k] == nil { full[k] = (node.fen, nil) }
        } } }
        let treeWire: [[String: Any]] = variations.branches.map { key, nodes in
            let (atFen, atPly) = full[key] ?? (key, nil)
            let vars: [[String: Any]] = nodes.map { head in
                ["uci": head.uci, "san": head.san, "fen": head.fen,
                 "line": head.line.map { ["uci": $0.uci, "san": $0.san, "fen": $0.fen] }]
            }
            var branch: [String: Any] = ["at_fen": atFen, "variations": vars]
            if let atPly { branch["at_ply"] = atPly }
            return branch
        }
        return ["session": session as Any, "fen": displayedFen, "cursor": lineCursor,
                "in_variation": isInVariation, "line": lineWire, "tree": treeWire, "pov": povColor]
    }

    /// Resume: rebuild the exact tree + cursor from a replayed view. Idempotent — the forest is
    /// keyed by branch-fen, so re-adding a known sideline is a no-op (contract: re-hydration
    /// round-trips). Runs on the initial snapshot's `view` event, into a freshly-cleared line.
    private func hydrateView(_ v: ViewSnapshot) {
        // 1. Rebuild the forest: every branch's sidelines, each as its own linked VarNode chain.
        var forest = VariationForest()
        for branch in v.tree {
            for variation in branch.variations {
                let nodes = variation.line.map { VarNode(uci: $0.uci, san: $0.san, fen: $0.fen) }
                for k in 0 ..< max(0, nodes.count - 1) { nodes[k].next = nodes[k + 1] }
                if let head = nodes.first { _ = forest.add(head, from: branch.atFen) }
            }
        }
        // 2. Rebuild the active segment stack from the resolved line: each `branch` move starts a
        // segment branching at the prior index; its nodes are the forest's own chain (buildLine
        // re-truncates for nesting, so passing the full chain is correct).
        var stack: [VarSegment] = []
        for (i, m) in v.line.enumerated() where m.branch && i >= 1 {
            let fromFen = v.line[i - 1].fen
            guard let uci = m.uci, let head = forest.existing(uci, from: fromFen) else { continue }
            stack.append(VarSegment(branchLineIndex: i - 1, nodes: head.line))
        }
        variations = forest
        collapseTo = nil; openCaret = nil
        if stack.isEmpty {
            varStack = []; varCursor = 0
            viewIndex = v.cursor >= liveIndex ? nil : v.cursor   // restore the mainline browse position
        } else {
            varStack = stack
            varCursor = min(max(v.cursor, 0), max(0, buildLine(stack).count - 1))
        }
    }

    /// Drop a piece: show the move optimistically, then let the MCP adjudicate. A wrong drill move
    /// stays on the board (Retry reverts it); a correct/non-drill move is superseded by the live board.
    /// A pawn reaching the last rank first pops the promotion picker (no silent auto-queen).
    private func playMove(_ from: String, _ to: String) {
        if ChessMove.isPromotion(displayedFen, from: from, to: to) {
            pendingPromotion = PendingPromotion(from: from, to: to)   // ask which piece, then resolve
            return
        }
        playMoveResolved(from, to, promotion: nil)
    }

    /// The player picked a promotion piece from the picker → play the move with it.
    private func completePromotion(_ piece: Character) {
        guard let p = pendingPromotion else { return }
        pendingPromotion = nil
        playMoveResolved(p.from, p.to, promotion: piece)
    }

    private func playMoveResolved(_ from: String, _ to: String, promotion: Character?) {
        guard let applied = ChessMove.apply(displayedFen, from: from, to: to, promotion: promotion) else { return }
        expectCoachBeat = false                        // a move gets ✓+local praise / ✗+Why? — no coach beat
        let solve = displayedFen                      // the position being solved (before the move)
        // A NEW attempt supersedes the prior Retry-guard. `solveFen` pins the board on the puzzle root
        // through a late coach repaint after Retry, but it OUTRANKS the move line in `displayedFen` — so
        // if it lingers into this move, the instant the optimistic hold drops on the server's board it
        // re-shows the puzzle root for a beat (the "wrong → Retry → right flashes the original" bug).
        // Clear it now; a wrong move re-arms it below. (The move itself is applied to `solve`, captured
        // above, so this doesn't change what's played.)
        solveFen = nil; lastMoveWrong = false
        heldWrong = applied.fen                       // optimistic — the piece moves immediately
        // Optimistic "you played" bubble too — render it the instant the move lands, don't wait for
        // the server. The verdict badge + captured-piece detail fill in when the server echo (same
        // clientId) reconciles. SAN/after-fen are computed locally (ChessMove).
        let san = ChessMove.san(solve, from: from, to: to, promotion: promotion)
        let uci = applied.uci                         // includes the promotion suffix (e.g. b7b8q) — the
                                                      // server needs it, or a bare b7b8 reads as underpromotion
        let clientId = UUID().uuidString
        // Adjudicate locally against the downloaded tree for an INSTANT badge — no /move wait. Nil
        // when there's no drill (freeform) → no badge. The backend re-adjudicates and reconciles.
        let verdict = walker?.adjudicate(uci: uci, san: san)
        stream?.pushLocalYouMoveBeat("Played \(san)", move: san, fen: applied.fen,
                                     correct: verdict?.correct, clientId: clientId)
        if walker != nil {
            // LOCAL PUZZLE: everything here is client-side — the walker adjudicated, we play both sides,
            // and the move silently persists via the `displayedFen` onChange (setBoardPosition + setView).
            // NO `/move`, no LLM. The only server LLM call in puzzle mode is the on-demand "Why?".
            if verdict?.correct == false {                    // wrong → hold + Retry + on-demand Why
                solveFen = solve; lastMoveWrong = true; lastMoveUci = uci
                _ = variations.add(VarNode(uci: uci, san: san, fen: applied.fen), from: solve)   // save the try
                Task { await coach?.setView(viewSnapshot()) }   // a held wrong move doesn't move the board, so
                                                                // sync the variation explicitly
            } else if verdict?.correct == true {              // right → local praise + play the reply locally
                stream?.pushLocalBeat(Praise.next(), tone: "praise")
                if var line = localLine {
                    let studentIdx = line.count               // index the student move lands at
                    line.append(Ply(n: line.count, san: san, uci: uci, fen: applied.fen))
                    heldWrong = nil
                    if let reply = walker?.lastReply, let rfen = reply.then.fen {
                        line.append(Ply(n: line.count, san: reply.san, uci: reply.uci, fen: rfen))
                        // Set the line AND pin the cursor to the student's move in the SAME cycle, so the
                        // board never flashes the reply — it holds on your move, then eases to the tip
                        // (viewIndex → nil) so the opponent's piece SLIDES in.
                        localLine = line
                        pieceIdMaps = PieceTrack.idMaps(line)   // SYNC — the `.task` recompute is async and
                                                               // wouldn't be ready in time, so the slide had
                                                               // no stable ids and the piece jumped instead
                        viewIndex = studentIdx
                        stream?.pushLocalOpponentMoveBeat(reply.san, fen: rfen)   // Lucena's move (chip, no tick)
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.3)) { viewIndex = nil }
                        }
                    } else {
                        localLine = line                      // line ended (a one-move win) — no reply to play
                    }
                    if walker?.awaitingContinue == true {     // a branch is solved, but the opponent has
                                                              // ANOTHER defence — offer Continue (drills it)
                        continueBranchPending = true
                        stream?.pushLocalBeat("Good — but the opponent has another defence. Try it.", tone: "coach")
                    } else if verdict?.finished == true {     // solved every line — a LOCAL closing beat, no LLM
                        stream?.pushLocalBeat("Solved — nicely done.", tone: "praise")
                        if hadPoisonedLine { poisonedLineNudge = true }
                        if (stream?.activityDepth ?? 1) == 1 { baseConceptClosed = true }
                    }
                }
            }
        } else {
            // FREEFORM / non-drill move → the server handles it (narration lives there).
            Task {
                let r = await coach?.playMove(uci, fen: solve, clientId: clientId)
                if r?.drill == true && r?.correct == false {
                    solveFen = solve; lastMoveWrong = true; lastMoveUci = uci
                } else {
                    solveFen = nil; lastMoveWrong = false
                    continueBranchPending = (r?.awaitContinue == true)
                    if r?.drill == true && r?.finished == true {
                        await coach?.drillSolved(fen: board?.fen ?? solve)
                        if hadPoisonedLine { poisonedLineNudge = true }
                        if (stream?.activityDepth ?? 1) == 1 { baseConceptClosed = true }
                    }
                }
            }
        }
    }

    /// The "Continue" button in a LOCAL puzzle: the opponent had another defence. The mainline stays the
    /// line you already solved; this opens the sibling defence as a SIDE-LINE you're now IN and solving.
    /// The walker pops the held sibling (the deferred backtrack); we branch a variation at that point,
    /// animate the opponent's defence in, and hand solving to `playDrillVariation`. No server, no LLM.
    private func continueBranchLocally() {
        guard let cont = walker?.continueBranch() else { return }
        let branchIdx = cont.branchLen - 1                 // the shared position the sibling branches FROM
        let line = displayLine
        guard line.indices.contains(branchIdx) else { return }
        let branchFen = line[branchIdx].fen
        let sibNode = VarNode(uci: cont.defenseUci, san: cont.defenseSan, fen: cont.afterFen)
        let attached = variations.add(sibNode, from: branchFen)   // dedup: re-enters an existing sibling
        // Switching to a sibling at the SAME branch replaces the current side-line rather than stacking.
        if varStack.last?.branchLineIndex == branchIdx { varStack.removeLast() }
        varStack.append(VarSegment(branchLineIndex: branchIdx, nodes: attached.line))
        solvingSiblingBranch = true
        openCaret = nil; collapseTo = nil
        varCursor = branchIdx                              // hold on the branch point, then slide it in
        stream?.pushLocalOpponentMoveBeat(cont.defenseSan, fen: cont.afterFen)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) { varCursor = displayLine.count - 1 }
        }
        Task { await coach?.setView(viewSnapshot()) }
    }

    /// Extend the active side-line's tip with a node (keeping the linked-list `next` consistent). When
    /// `advance`, snap the cursor to the new tip (an instant show — the SLIDE is driven by the caller
    /// animating `varCursor` afterward, exactly like the mainline reply path).
    private func appendVariationTip(_ node: VarNode, advance: Bool) {
        guard !varStack.isEmpty else { return }
        varStack[varStack.count - 1].nodes.last?.next = node
        varStack[varStack.count - 1].nodes.append(node)
        if advance { varCursor = displayLine.count - 1 }
    }

    /// A drill answer typed into a sibling side-line: adjudicate via the walker (the sole local
    /// adjudicator), extend the side-line, and play the opponent's reply INTO the same side-line —
    /// mirroring `playMoveResolved`'s local branch, but on `varStack` instead of `localLine`.
    private func playDrillVariation(_ from: String, _ to: String) {
        guard let applied = ChessMove.apply(displayedFen, from: from, to: to, promotion: nil) else { return }
        let solve = displayedFen
        let san = ChessMove.san(solve, from: from, to: to, promotion: nil)
        let uci = applied.uci
        let clientId = UUID().uuidString
        expectCoachBeat = false
        let verdict = walker?.adjudicate(uci: uci, san: san)
        stream?.pushLocalYouMoveBeat("Played \(san)", move: san, fen: applied.fen,
                                     correct: verdict?.correct, clientId: clientId)
        if verdict?.correct == false {                     // wrong → hold + Retry + save the try under "?"
            heldWrong = applied.fen                         // optimistic (displayedFen shows it in-side-line)
            lastMoveWrong = true; lastMoveUci = uci
            _ = variations.add(VarNode(uci: uci, san: san, fen: applied.fen), from: solve)   // persists as a variation
        } else if verdict?.correct == true {               // right → praise, play the reply, keep drilling
            heldWrong = nil
            stream?.pushLocalBeat(Praise.next(), tone: "praise")
            appendVariationTip(VarNode(uci: uci, san: san, fen: applied.fen), advance: true)   // your move (instant)
            if let reply = walker?.lastReply, let rfen = reply.then.fen {
                appendVariationTip(VarNode(uci: reply.uci, san: reply.san, fen: rfen), advance: false)
                stream?.pushLocalOpponentMoveBeat(reply.san, fen: rfen)   // Lucena's move (chip, no tick)
                DispatchQueue.main.async {                 // hold on your move, then SLIDE the reply in
                    withAnimation(.easeInOut(duration: 0.3)) { varCursor = displayLine.count - 1 }
                }
            }
            if walker?.awaitingContinue == true {          // yet another defence at this point — offer Continue
                continueBranchPending = true
                stream?.pushLocalBeat("Good — but the opponent has another defence. Try it.", tone: "coach")
            } else if verdict?.finished == true {          // every line solved — closing beat, leave the side-line up
                solvingSiblingBranch = false
                stream?.pushLocalBeat("Solved — nicely done.", tone: "praise")
                if (stream?.activityDepth ?? 1) == 1 { baseConceptClosed = true }
            }
        }
        Task { await coach?.setView(viewSnapshot()) }
    }

    /// The action buttons live in the CHAT (not on the board): Retry (red — the only red button) and
    /// "show me the trap" (black, like every other button). Shown at the foot of the conversation.
    /// True until the server has loaded (Maia included) AND streamed the full initial snapshot — so
    /// the chat reveals in one shot, never piecemeal as board/beats/history arrive event by event.
    private var isWarmingUp: Bool { !(stream?.ready ?? false) }

    /// The chat's warm-up state: a full-height CHAT skeleton (alternating coach / player message
    /// blocks) that fills the panel down to the input box, so it reads as "a conversation loading",
    /// not three lonely lines. Shimmers while the server + Maia come up.
    private var coachLoading: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            skeletonMessage(coach: true,  widths: [230, 300, 180])
            skeletonMessage(coach: false, widths: [150])
            skeletonMessage(coach: true,  widths: [280, 220])
            skeletonMessage(coach: false, widths: [190])
            skeletonMessage(coach: true,  widths: [260, 300, 150])
            Spacer(minLength: 0)
            Text(verbatim: "Warming up the engine…")
                .font(Theme.Typography.label)
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One skeleton chat bubble — a left-aligned coach block or a right-aligned player block.
    private func skeletonMessage(coach: Bool, widths: [CGFloat]) -> some View {
        VStack(alignment: coach ? .leading : .trailing, spacing: Theme.Spacing.xs) {
            ForEach(widths.indices, id: \.self) { i in ShimmerBar(width: widths[i]) }
        }
        .frame(maxWidth: .infinity, alignment: coach ? .leading : .trailing)
    }

    /// Example starter prompts, shown on a fresh (empty) session — tap to send.
    private static let starterPrompts = [
        "Give me a puzzle",
        "Let's learn about endgames today",
        "Play a friendly match against an 1800 bot",
    ]

    /// The empty-session state: a quiet prompt + tappable example chips, so a new session isn't a blank
    /// panel. Tapping a chip sends it as the first turn.
    private var emptySessionPrompts: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            Text(verbatim: "Try one of these to get started")
                .font(Theme.Typography.label)
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.ink.opacity(0.5))
            ForEach(Self.starterPrompts, id: \.self) { p in promptChip(p) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func promptChip(_ text: String) -> some View {
        Button { sendPrompt(text) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "sparkles").foregroundStyle(Theme.Palette.gold)
                Text(verbatim: text)
                    .font(Theme.Typography.youBubble)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.paperDeep)
            .overlay(Rectangle().stroke(Theme.Palette.ink.opacity(0.3), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(coachSending || session == nil)
    }

    /// Send a starter prompt as the first turn (mirrors the input pane's send).
    private func sendPrompt(_ text: String) {
        guard let session, let coach, !coachSending else { return }
        withAnimation(.easeInOut(duration: 0.25)) { conversationStarted = true }   // dismiss the tips
        expectCoachBeat = true                          // a text turn DOES expect a coach beat
        coachSending = true
        Task {
            _ = await coach.sendTurn(text: text, sessionId: session)
            await MainActor.run { coachSending = false }
        }
    }

    /// The chat footer: the live "what the coach is doing" line (tool-grounded), then any action
    /// buttons. Both flow inside the beats scroll, at the very bottom.
    @ViewBuilder private var chatFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            coachStatusRow
            chatActions
        }
    }

    /// A single, replacing status line — a pulsing square dot + the grounded phase text — shown only
    /// while the coach is working. Falls back to "Thinking…" between tool calls.
    @ViewBuilder private var coachStatusRow: some View {
        // Show while a tool is running (stable `coachStatus`) OR while the coach is otherwise working
        // (title dance) — falling back to "Thinking…" for the pure-thinking gaps. `coachWorking` is
        // debounced to 1s so this doesn't flicker between title updates.
        if coachWorking || stream?.coachStatus != nil {
            HStack(spacing: Theme.Spacing.sm) {
                PulsingSquareDot(color: Theme.Palette.ink.opacity(0.7))   // only the dot animates
                Text(verbatim: stream?.coachStatus ?? "Thinking…")
                    .font(Theme.Typography.label)
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.6))
                    .contentTransition(.identity)      // text swaps instantly — never animates
                    .animation(nil, value: stream?.coachStatus)
                Spacer()
            }
            .transition(.identity)                     // row appears/leaves without a fade
        }
    }

    @ViewBuilder private var chatActions: some View {
        // The back-to-previous-concept buttons are gated behind the feature flag (disabled for now), so
        // their triggers (rabbit-hole depth / a just-closed base concept) don't render the action row.
        let showBack = Self.showBackToPreviousConcept && ((stream?.activityDepth ?? 1) > 1 || baseConceptClosed)
        if lastMoveWrong || poisonedLineNudge || showBack || continueBranchPending {
            HStack(spacing: Theme.Spacing.md) {
                if continueBranchPending {
                    // Solved this branch — walk the opponent's next defence on click. Local walk does the
                    // backtrack itself (no server); a legacy server drill (no walker) still asks the server.
                    chatButton("Continue", icon: Theme.Symbol.chevronRight, background: Theme.Palette.coachBlue) {
                        continueBranchPending = false
                        if walker != nil { continueBranchLocally() } else { coach?.continueBranch() }
                    }
                }
                if Self.showBackToPreviousConcept {
                    if (stream?.activityDepth ?? 1) > 1 {
                        // Inside a rabbit-hole activity — offer to go back to what the player was looking at.
                        // The server restores the parent workspace over /state. Shown the whole time you're
                        // in the rabbit-hole (you can bail anytime, not only after the drill closes).
                        chatButton("Back to the previous concept", icon: "arrow.uturn.backward",
                                   background: Theme.Palette.ink) {
                            Task { await coach?.openActivity(0) }
                        }
                    } else if baseConceptClosed {
                        // No rabbit-hole to pop (base frame), but a concept just closed — going back means the
                        // standard start position (the player has nothing else to return to).
                        chatButton("Back to the previous concept", icon: "arrow.uturn.backward",
                                   background: Theme.Palette.ink) {
                            baseConceptClosed = false
                            Task { await coach?.resetToStart() }
                        }
                    }
                }
                if lastMoveWrong {
                    chatButton(Strings.StudySession.retry, icon: Theme.Symbol.retry,
                               background: Theme.Palette.mistakeRed) {   // red — the one exception
                        heldWrong = nil; lastMoveWrong = false           // the wrong try persists under "?"
                    }
                    // v1: the wrong-move "why" is ON DEMAND now (not auto). Why? → `explain` regenerates
                    // today's refutation-line explanation for the held move.
                    chatButton("Why?", icon: "questionmark.circle", background: Theme.Palette.ink) {
                        guard let session, let move = lastMoveUci else { return }
                        let fen = solveFen ?? displayedFen
                        expectCoachBeat = true          // Why? DOES expect a coach beat (the explanation)
                        coachSending = true
                        Task {
                            _ = await coach?.explain(fen: fen, move: move, correct: false, sessionId: session)
                            await MainActor.run { coachSending = false }
                        }
                    }
                }
                if poisonedLineNudge {
                    chatButton(Strings.StudySession.showMeTheTrap, icon: Theme.Symbol.chevronRight,
                               background: Theme.Palette.ink) {          // black, like all other buttons
                        poisonedLineNudge = false
                        // Load the poisoned line as a local variation and animate into its first move.
                        // Client-side render only — the server no longer arms a punish-drill for this.
                        _ = showPoisonedLineVariation()
                    }
                }
                Spacer()
            }
        }
    }

    private var promotingWhite: Bool {
        (displayedFen.split(separator: " ").dropFirst().first.map(String.init) ?? "w") == "w"
    }

    /// The promotion picker — a small card floated over the board with the four choices, drawn with the
    /// SAME piece art as the board (assets "wQ"/"bN"/…). Codes are always uppercase (ChessMove derives
    /// the colour + lowercases for UCI).
    @ViewBuilder private var promotionPicker: some View {
        let side = promotingWhite ? "w" : "b"
        let choices: [Character] = ["Q", "R", "B", "N"]
        ZStack {
            Rectangle().fill(Theme.Palette.ink.opacity(0.3))          // dim the board
                .contentShape(Rectangle())
                .onTapGesture { pendingPromotion = nil }             // tap off = cancel (nothing was played)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(choices, id: \.self) { code in
                    Button { completePromotion(code) } label: {
                        Image("\(side)\(code)")                       // same asset the board renders
                            .resizable().interpolation(.high).scaledToFit()
                            .frame(width: 52, height: 52)
                            .frame(width: 60, height: 60)
                            .background(Theme.Palette.paper)
                            .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.paper)
            .overlay(Rectangle().stroke(Theme.Palette.ink, lineWidth: 2))
            .shadow(color: Theme.Palette.ink.opacity(0.5), radius: 18, x: 0, y: 10)
        }
    }

    private func chatButton(_ text: LocalizedStringKey, icon: String, background: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(text) } icon: { Image(systemName: icon) }
                .font(Theme.Typography.label)
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.paper)
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.md)
                .background(background)
        }
        .buttonStyle(.plain)
    }

    /// The terminal sits at the foot, bottom-anchored, and grows *upward* into the beats area with
    /// content — up to half the column (`columnHeight * 0.5`).
    private func beatsColumn(columnHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // The coach CONVERSATION is the only thing that changes between the session and a puzzle. On a
            // switch it SLIDES IN as one block — entering a puzzle from the right, going back from the
            // left. It's a SINGLE pane driven by an offset (not two transitioning copies): a keyed
            // transition would briefly render the old and new pane at once, and both read the same live
            // `beats`, so every message showed twice mid-slide. One pane → one copy → nothing doubles.
            // The board, eval bar, rail and input never move.
            tabBar                               // Coach | Analysis — PINNED at the top, never moves or slides
            // The ONE animation on an activity switch: the coach conversation slides in RIGHT-TO-LEFT.
            // Keyed on the in-view activity — the new pane's insertion transition starts it off-screen to
            // the right and eases it home (so it never flashes at home first); the old pane is removed
            // instantly (`.identity`) so nothing slides beside it. Driven by StateStream's own animation
            // (it applies the `activity` event inside withAnimation), so there's no second animator here.
            // The ZStack is the stable, CLIPPED slot; board + rail + tabs + input never move.
            ZStack(alignment: .topLeading) {         // TOP-align: a long reopened pane must not be centered
                conversationPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(stream?.activeIdx ?? 0)
                    // The PUZZLE pane (idx > 0) sits ON TOP and always slides horizontally — in from the
                    // right to COVER the session (enter/reopen), out to the right to UNCOVER it (back). The
                    // SESSION pane (idx 0) sits beneath and never moves: on back it's simply revealed. Both
                    // are keyed to the pane's OWN index, so the outgoing puzzle keeps its slide + top z-order.
                    .zIndex(Double(stream?.activeIdx ?? 0))
                    .transition((stream?.activeIdx ?? 0) > 0 ? .move(edge: .trailing) : .identity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // The chatbox is GONE (owner, v1 wiring): free text was the chat
            // era; instructions live in the margin's command field.
        }
    }

    /// One coach conversation — the session's or a puzzle's. This whole block is what slides when the
    /// in-view activity changes (see `beatsColumn`); a faint wash + the drill header mark a puzzle.
    private var conversationPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if inActivity || drillGoverns { drillHeader }   // back + title; rides along with the slide
            Group {
                switch rightTab {
                case .coach:
                    if !(inActivity || drillGoverns) {
                        // v1: the margin IS the coach surface (owner wiring
                        // step a: the conversation view goes away).
                        MarginLiveView(fen: displayedFen, sessionId: session, coach: coach, live: viewIndex == nil)
                    } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        moveHead
                            // The caption line appears/disappears when the board changes (e.g. a reopen
                            // swaps to the puzzle's board). Make that change INSTANT so it can't drift the
                            // conversation up-by-a-line WHILE the pane is sliding in.
                            .animation(nil, value: stream?.board?.caption)
                        if isWarmingUp {
                            coachLoading            // server + Maia still coming up → chat skeleton
                                .transition(.opacity)
                        } else if beats.isEmpty && !conversationStarted {
                            emptySessionPrompts     // fresh session → tappable starter prompts
                                .transition(.opacity)
                        } else {
                            // The conversation scrolls; the coach status + action buttons are PINNED
                            // just below it. Buttons rendered INSIDE the ScrollView's content don't
                            // reliably receive clicks on macOS (Retry / "show me the trap" fired their
                            // labels but never their actions), so they live outside the scroll now.
                            BeatsColumnView(beats: beats, history: history, onMoveTap: snapToMove,
                                            onCardTap: { idx in Task { await coach?.openActivity(idx) } },
                                            // A REOPENED puzzle (in an activity, no longer live-drilling) opens
                                            // at the TOP — its own start — so a long saved conversation doesn't
                                            // scroll down on appear (the "goes up"). Live/base follows the bottom.
                                            scrollAnchor: (inActivity && stream?.mode != "coach") ? .top : .bottom)
                            chatFooter   // status + Retry / Why / show-me-the-trap — outside the scroll
                        }
                    }
                    }
                case .analysis:
                    AnalysisView(engineLines: stream?.engineLines, currentFen: displayedFen,
                                 analysisOn: $analysisOn, plies: history,
                                 currentIndex: currentPlyIndex) { i in
                        viewIndex = i >= liveIndex ? nil : i
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(inActivity ? Theme.Spacing.md : 0)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(inActivity ? Theme.Palette.ink.opacity(0.04) : Color.clear))
    }

    /// A drill governs the chat: coach mode is live, or a what-if excursion has it parked
    /// (`suspended`) — the header stays up so the drill remains visible (and leavable) either way.
    private var drillGoverns: Bool {
        stream?.mode == "coach" || (stream?.modeSuspended ?? false)
    }

    private var drillTitle: LocalizedStringKey {
        // Prefer the live lesson type; fall back to the in-view activity's kind so a REOPENED (solved,
        // freeform) puzzle still titles correctly — its mode is no longer "coach".
        switch stream?.modeLessonType ?? (inActivity ? stream?.activityKind : nil) {
        case "puzzle":  return Strings.StudySession.drillPuzzle
        case "endgame": return Strings.StudySession.drillEndgame
        case "midgame": return Strings.StudySession.drillMidgame
        case "opening": return Strings.StudySession.drillOpening
        default:        return Strings.StudySession.drillGeneric
        }
    }

    /// The drill header — the mode made explicit: a back button (leave the drill → freeform; the
    /// lesson goes `open`, resumable later) and the lesson's title. Purely additive; the conversation
    /// below behaves exactly as before.
    private var drillHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                Task { await coach?.leaveLesson() }
            } label: {
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: Theme.Symbol.back)
                        .font(Theme.Typography.labelSmall)
                    Text(Strings.StudySession.back)
                        .font(Theme.Typography.label)
                        .tracking(Theme.Tracking.label)
                        .textCase(.uppercase)
                }
                .foregroundStyle(Theme.Palette.ink70)
            }
            .buttonStyle(.plain)
            Text(drillTitle)
                .font(Theme.Typography.serif(16, .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
        }
    }

    /// The Coach | Analysis tab switcher (a gold/blue underline marks the active tab).
    private var tabBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(RightTab.allCases, id: \.self) { tab in
                Button { rightTab = tab } label: {
                    Text(tab.title)
                        .font(Theme.Typography.label)
                        .tracking(Theme.Tracking.label)
                        .textCase(.uppercase)
                        .foregroundStyle(tab == rightTab ? Theme.Palette.ink : Theme.Palette.ink45)
                        .padding(.bottom, Theme.Spacing.xs)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(tab == rightTab ? Theme.Palette.coachBlue : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.ink22).frame(height: 1) }
    }

    /// The beats-column header — the board's caption (coach-set) and whose move it is, both grounded
    /// in the live board. Nothing before a board exists.
    @ViewBuilder private var moveHead: some View {
        // The "to move" label now sits above the move navigator; this keeps only the coach's board
        // caption (an arrow/idea title) at the head of the chat column, when present.
        if let caption = board?.caption, !caption.isEmpty {
            Text(verbatim: caption)
                .font(Theme.Typography.moveLg)
                .foregroundColor(Theme.Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Your move" when it's the player's turn in a drill, else "White/Black to move" — from the FEN.
    private func turnLabel(_ board: BoardState) -> LocalizedStringKey {
        switch board.terminal {   // a terminal position has no move — never say "X to move"
        case "checkmate": return Strings.StudySession.checkmate
        case "stalemate": return Strings.StudySession.stalemate
        default: break
        }
        let side = board.sideToMove
        if let solve = stream?.drill?.sideToSolve, solve.hasPrefix(side) {
            return Strings.StudySession.yourMove
        }
        return side == "w" ? Strings.StudySession.whiteToMove : Strings.StudySession.blackToMove
    }
}

/// The right-column tabs: the MARGIN (the v1 coach surface — the
/// conversation view is retired) and the analysis panel.
private enum RightTab: CaseIterable {
    case coach, analysis
    var title: LocalizedStringKey {
        switch self {
        case .coach: return "Position"
        case .analysis: return Strings.StudySession.tabAnalysis
        }
    }
}

/// Stable per-piece identities across a move line. Each physical piece gets an id that FOLLOWS it
/// from ply to ply, so the board can key a piece on its identity (not its square) and let SwiftUI
/// slide it when the position changes — correctly for any move type, and independent of timing (so
/// fast stepping can't mis-slide a piece, unlike a per-move remap that races its own animation).
enum PieceTrack {
    /// `[ply][algebraicSquare: id]`. Ids are threaded through each ply's `uci` (captures drop the
    /// captured id; castling moves the rook's id; en passant drops the taken pawn; promotion keeps
    /// the pawn's id). Falls back to a fresh relabel if a ply lacks a usable uci.
    static func idMaps(_ plies: [Ply]) -> [[String: String]] {
        guard let first = plies.first else { return [] }
        var next = 0
        func fresh() -> String { defer { next += 1 }; return "pc\(next)" }
        var idmap: [String: String] = [:]
        for sq in occupied(first.fen).keys.sorted() { idmap[sq] = fresh() }
        var maps = [idmap]
        for k in 1..<plies.count {
            idmap = advance(idmap, prevFen: plies[k - 1].fen, curFen: plies[k].fen,
                            uci: plies[k].uci, mint: fresh)
            maps.append(idmap)
        }
        return maps
    }

    /// Carry a square→id map across ONE move: the mover's id follows it (captures drop the taken id,
    /// castling carries the rook, en passant drops the taken pawn, promotion keeps the id), then the
    /// map is reconciled against the resulting board. Shared by the mainline pass and variation descent.
    static func advance(_ map: [String: String], prevFen: String, curFen: String,
                        uci: String?, mint: () -> String) -> [String: String] {
        let prev = occupied(prevFen), cur = occupied(curFen)
        var m = map
        if let uci, uci.count >= 4 {
            let src = String(uci.prefix(2))
            let dst = String(uci.dropFirst(2).prefix(2))
            let movedId = m.removeValue(forKey: src)
            if prev[src]?.uppercased() == "P", src.first != dst.first, prev[dst] == nil,
               let df = dst.first, let sr = src.dropFirst().first {
                m.removeValue(forKey: String(df) + String(sr))          // en passant victim
            }
            m[dst] = movedId ?? mint()
            if prev[src]?.uppercased() == "K", let sf = src.first?.asciiValue,
               let df = dst.first?.asciiValue, abs(Int(sf) - Int(df)) == 2 {
                let rank = String(src.dropFirst())
                let (rs, rd) = dst.first == "g" ? ("h" + rank, "f" + rank) : ("a" + rank, "d" + rank)
                let rid = m.removeValue(forKey: rs)
                m[rd] = rid ?? mint()                                    // castling rook
            }
        } else {
            m = [:]; for sq in cur.keys.sorted() { m[sq] = mint() }
        }
        for sq in cur.keys where m[sq] == nil { m[sq] = mint() }
        for sq in Array(m.keys) where cur[sq] == nil { m.removeValue(forKey: sq) }
        return m
    }

    /// The occupied algebraic squares in a FEN (for seeding a fresh id map).
    static func squares(_ fen: String) -> [String] { Array(occupied(fen).keys) }

    /// `[algebraicSquare: pieceChar]` from a FEN's placement field.
    private static func occupied(_ fen: String) -> [String: Character] {
        var m: [String: Character] = [:]
        let field = fen.split(separator: " ").first.map(String.init) ?? fen
        for (ri, rank) in field.split(separator: "/").enumerated() {   // ri 0 = rank 8
            var file = 0
            for ch in rank {
                if let n = ch.wholeNumberValue { file += n; continue }
                m[String(UnicodeScalar(UInt8(97 + file))) + String(8 - ri)] = ch
                file += 1
            }
        }
        return m
    }
}

#Preview {
    StudySessionScreen()
        .environment(\.stateStream, StateStream.stub())   // empty state — no board, no beats yet
        .frame(width: Theme.Size.windowDefault.width, height: Theme.Size.windowDefault.height)
}

/// A pawn drop that reached the last rank, awaiting the player's piece choice from the picker.
private struct PendingPromotion { let from: String; let to: String }
