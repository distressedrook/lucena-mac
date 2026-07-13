# mac-client — native macOS client

A thin native SwiftUI client. It renders the board + coaching beats streamed from the backend and
sends the player's input; it holds no chess truth and never drives the model. The prior client
(chat input, board/beats rendering over SSE, REST bridge) is archived in `legacy/app/` and will be
reused/reshaped here once the backend API contract is locked.

Design in progress — see `docs/`.
