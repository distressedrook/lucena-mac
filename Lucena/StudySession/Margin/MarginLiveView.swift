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
            guard let data = await coach.margin(fen: fen, sessionId: sessionId) else { return }
            if let decoded = try? JSONDecoder().decode(MarginContent.self, from: data) {
                withAnimation(.easeInOut(duration: 0.15)) { content = decoded }
            }
        }
    }
}
