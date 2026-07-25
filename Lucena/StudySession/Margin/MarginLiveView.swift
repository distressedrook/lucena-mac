import SwiftUI

/// The LIVE margin — fetches /margin for the position under the navigator
/// cursor and renders it. Keeps the last content while a fetch is in flight
/// (no spinners on paper); a fetch that fails leaves the page as it was.
struct MarginLiveView: View {
    let fen: String?
    let sessionId: String?
    let coach: CoachBridge?

    @State private var content: MarginContent?

    var body: some View {
        Group {
            if let content {
                MarginColumnView(content: content)
            } else {
                Color.clear                      // bare paper until the first answer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: fen) {
            guard let fen, let coach else { return }
            // First answer is instant; while the deep layer computes, poll
            // gently until the plans land or we move on. EVERY position polls
            // — a variation or a scrub gets the same cycle as the live game
            // (owner 2026-07-26: "nothing is happening when there is a
            // variation"); the server's latest-wins rule is what keeps the
            // roll worker from grinding on positions we've navigated past.
            for attempt in 0..<20 {
                guard !Task.isCancelled else { return }
                guard let data = await coach.margin(fen: fen, sessionId: sessionId),
                      let decoded = try? JSONDecoder().decode(MarginContent.self, from: data)
                else { return }
                withAnimation(.easeInOut(duration: 0.15)) { content = decoded }
                guard decoded.plansPending else { return }
                try? await Task.sleep(for: .seconds(attempt == 0 ? 1.5 : 2.5))
            }
        }
    }
}
