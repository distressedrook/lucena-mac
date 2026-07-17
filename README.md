# mac-client — native macOS client

A thin native SwiftUI client for Lucena. It renders the board and the coach's beats streamed from the
backend and sends the player's input — it holds **no chess truth** and **never drives the model**. All
grounding and reasoning live in the backend + engine; the app is a renderer with a live connection.

## What it does

- **Board + move play** — drag or tap-to-move on `SessionBoardView`; a played move is pushed to the
  backend (REST `/move`), which adjudicates it (drill) or reads it (freeform) and streams the result.
- **Coaching beats** — the coach's turn arrives as beats over the live socket, rendered by
  `BeatsColumnView` as light Markdown with clickable figurine move-chips, plus the in-flow footer
  (Retry, show-me-the-trap).
- **Chat** — free-text questions to the coach via `ChatInputPaneView`.
- **Analysis + navigation** — an eval readout, a move navigator with variations, and an analysis pane.
- A thinking halo while the coach works, and an app-authored "didn't catch that" nudge if a turn ends
  without a beat.

## Shape

```
Lucena/
├── Support/         CoachBridge (app→server: WS turn/explain/position/view/input + REST /move,/drill),
│                    StateStream (WS snapshot + deltas), AuthClient, ChessMove, Environment
├── StudySession/    StudySessionScreen + board, beats, move navigator, analysis, chat, mode rail
├── Models/          the wire/state model types
├── Theme/           "Annotated Board" — paper + ink, Lora (bundled), figurine glyphs for notation
└── Fonts/, Assets.xcassets/
```

The transport is the backend's WebSocket `/ws` (a snapshot on connect, then deltas) for the live
coaching loop, with REST for move adjudication, session lifecycle, and auth.

## Build

```
xcodebuild -project Lucena.xcodeproj -scheme Lucena \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Point it at a running backend (see the superrepo `../serve.sh`).
