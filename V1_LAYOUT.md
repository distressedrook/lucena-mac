# V1 layout — the Annotated Board (chat retired)

Owner decisions, 2026-07-24 design session. This supersedes the chat-primary
interface: the transcript column is retired; the coach becomes margin + rook +
command box. Rationale and rulings: the memory trail is in the session log;
the one-line version — *the stack's truth is structured; chat flattened it
through the least-trusted component. Panels carry truth, the rook carries
voice.*

## The window

```
┌──┬─────────────────────────────┬───────────────────────────────┐
│  │  ┌───────────────────────┐  │ MASTHEAD                      │
│r │ ▌│                       │  │ ····························· │
│a │ ▌│         board         │  │                               │
│i │ ▌│      (eval bar ▌)     │  │        THE MARGIN             │
│l │ ▌│                       │  │   (one position's content)    │
│  │ ▌│                       │  │                               │
│  │  └───────────────────────┘  │ ───────────────────────────── │
│  │  ◀ ◀◀  navigator strip ▶▶ ▶ │  🨂  [ command box…         ] │
└──┴─────────────────────────────┴───────────────────────────────┘
```

**No element is duplicated (owner ruling):**

| region | owns | never shows |
|---|---|---|
| board | geometry: pieces, arrows, highlights, eval bar | text |
| navigator (below board) | THE only move text — the existing flowing-line + caret + variations system, unchanged — plus badge glyphs | prose |
| margin (right) | the coach's read of the CURRENT position | move lists, history |
| command box (margin foot) | instructions in, rook one-liners' home base | questions (v2) |

## The margin: cursor-linked, never a transcript

The margin renders content for the position under the navigator cursor and
re-renders on every scrub. Anchoring is **by FEN** (beats carry `board_seq`;
`VarNode` carries `fen`), so it works identically inside a variation — play a
what-if and the margin reads *that* position.

Three states; salience picks:

### 1. resting — nothing clears the bar (the common case)

Always-true, deterministic, low ink. **The margin is never empty** (owner:
"I can always show the current state of the position"):

```
MIDDLEGAME · move 14
Roughly equal · material even
Carlsbad structure · calm

        🨂  (idle)

Try: “give me a puzzle”
```

| line | feed |
|---|---|
| phase + move | fen (trivial) |
| eval-in-words + material standing | `reads.material` standing + eval bucket words — never numbers |
| structure + character | `lucena-plans structures.classify` (30 named skeletons) + `dynamism` rating (DEAD→RAZOR, worded) |
| command hint | rotating from the intent registry |
| home chips (later) | continue-lesson, daily activity |

Whitespace is intentional (paper identity): a calm margin signals "nothing
needs your attention" — the most trust-building state the product has.
Resting lines set in the small grey register.

### 2. noted — facts/plans fired

Rook one-liner (tone-typed, ≤2 lines, hard budget) + collapsed card headers,
**at most one card open** (highest salience):

```
🨂 “Book ends here. This is the real game now.”

▸ PLAN FOR WHITE            ← plans sheet: six headed sections = six rows,
▸ POSITION FACTS (3)          open one at a time; NEVER flattened to prose
```

Cards render from artifacts, not prose: fact cards carry F-ids/squares
(tap → arrow on board), the plans card renders the sheet's own headed
sections. The lexicalizer's only job is captions (verified, template floor).

### 3. urgent — tactic / drill offer / blunder

Full-ink card with a button. Never a modal, never a mode flip (owner report:
the auto-puzzle hijack). The drill invitation pattern from the backend
(armed spec + nudge) is the canonical example:

```
┌─────────────────────────────┐
│ ⚔ White has a forcing win   │
│   in this position.         │
│              [ Drill it ]   │
└─────────────────────────────┘
```

## Navigator badges

Tiny glyphs on strip moves — markers, not words — so past moments stay
findable without a written record: ⚑ book left · ⚔ tactic was here ·
!? / ?? glyph classes (already computed). Click a badged move → the margin
shows that moment. This is the answer to "what did the coach say three moves
ago": scrub, don't scroll.

## The command box (instructions, not questions)

Closed verb set over existing machinery; free questions are v2.

| verb | backing |
|---|---|
| give me a puzzle | puzzle library / served_puzzle / banked |
| drill it | armed lesson spec (the nudge flow) |
| what are my stats | drill counters + mastery banking |
| endgame lesson / activity | activities + authored studies |
| show the plan / facts | open the margin card |
| analyze this game (+PGN) | gamepass |
| new game / flip board | app actions |

Guardrails: placeholder cycles real commands; autocomplete over known verbs
(the affordance teaches the grammar — questions wither because nothing
completes). Classifier = utterance → intent or the existing `unsupported`
polite decline; **zero position interpretation**. Every declined utterance is
logged — the cluster of unanswerable asks is the v2 roadmap sensor.

## The rook

The brand mark gets the job: small, margin-resident, three-ish poses keyed to
beat `tone` (praise / teach / correct) + idle. Speaks only what clears the
salience bar, ≤2 lines, always positioned as the *author of the margin* —
its lines appear as marginalia, never as a second stream. Anti-Clippy rule:
frequency is governed by salience thresholds, not by having something to say.

## Variations

Unchanged and load-bearing: the one-flowing-line + caret + Back model is THE
move UI. The margin follows the cursor onto any line (FEN anchoring). Wrong
drill tries keep their ?/✗ caret parking.

## v1 / v2 boundary

v1: everything above — no free-text questions anywhere.
v2: tap-generated question affordances (askable surface derived from
grounding coverage), stated-intent plan refutation (plan_foil: interactive,
not automatic), free text as instrumented escape hatch.

## Open items

- Salience thresholds per state transition (start: reuse fact-sheet salience;
  tactic/blunder always urgent).
- Backend: beats should carry structured card payloads (the plans sheet as
  sections, facts as F-id lists) instead of pre-flattened prose — the margin
  renders structure. Prose-flattening moves from the backend to nowhere.
- Whose-tactic nuance on the urgent card (nudge on own blunders: yes/no —
  parked from the drill-invitation fix).
- Validate the no-written-history trade in the first prototype.
