import SwiftUI

/// The LIVE margin — fetches /margin for the position under the navigator cursor and renders it.
/// Keeps the last content while a fetch is in flight (no spinners on paper); a fetch that fails
/// leaves the page as it was.
///
/// CACHED FOR THE SESSION (owner 2026-07-26: "can we also have front-end caching? while inside a
/// session? I don't want it to make calls each time a move is played"). A settled reading of a
/// position is the same reading every time — the backend caches it by fen for exactly that reason —
/// so once we have one, walking back over that position costs NO request at all: it is drawn from
/// memory, instantly. Only SETTLED readings are kept; a mid-roll answer is a loading state and
/// caching it would freeze the page on "reading the position…" forever.
struct MarginLiveView: View {
    let fen: String?
    let sessionId: String?
    let coach: CoachBridge?

    @State private var content: MarginContent?
    @State private var cache: [String: MarginContent] = [:]
    @State private var cachedFor: String?          // the chat this memory belongs to

    /// What this view is showing: a position, in a chat. Both matter — see the task below.
    private struct Target: Equatable { let fen: String?; let session: String? }

    /// Positions are keyed WITHOUT the clocks, the same rule the backend caches by — the same board
    /// reached again is the same reading.
    private static func key(_ fen: String) -> String {
        fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    var body: some View {
        Group {
            if let content {
                MarginColumnView(content: content)
            } else {
                Color.clear                      // bare paper until the first answer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Keyed on the CHAT as well as the position: switching conversations while the board
        // happens to show the same fen would otherwise not re-run this at all — SwiftUI keeps the
        // view's state — leaving the previous chat's reading on screen (Codex).
        .task(id: Target(fen: fen, session: sessionId)) {
            // A chat switch invalidates the memory: the epigraph is seeded per session, and a
            // reading belongs to the conversation it was taken in. BEFORE the guard — a switch
            // whose new position or socket has not landed yet still has to clear the old chat's
            // page, or it stays on screen until one does (Codex).
            if cachedFor != sessionId {
                cache.removeAll()
                content = nil
                cachedFor = sessionId
            }
            guard let fen, let coach else { return }
            if let hit = cache[Self.key(fen)] {
                content = hit                    // instant, and no request at all
                return
            }
            // First answer is instant; while the deep layer computes, poll gently until the plans
            // land or we move on. EVERY position polls — a variation or a scrub gets the same cycle
            // as the live game (owner 2026-07-26: "nothing is happening when there is a variation");
            // the server's latest-wins rule is what keeps the roll worker from grinding on positions
            // we have navigated past.
            for attempt in 0..<20 {
                guard !Task.isCancelled else { return }
                guard let data = await coach.margin(fen: fen, sessionId: sessionId),
                      let decoded = try? JSONDecoder().decode(MarginContent.self, from: data)
                else { return }
                withAnimation(.easeInOut(duration: 0.15)) { content = decoded }
                guard decoded.plansPending else {
                    remember(decoded, for: fen)
                    return
                }
                try? await Task.sleep(for: .seconds(attempt == 0 ? 1.5 : 2.5))
            }
        }
    }

    /// Keep a settled reading. Bounded: a long game visits a lot of positions, and each reading is
    /// a whole sheet.
    private func remember(_ c: MarginContent, for fen: String) {
        if cache.count >= 128 { cache.removeAll() }   // a session's worth; simplest honest bound
        cache[Self.key(fen)] = c
    }
}
