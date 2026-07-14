import Foundation

/// One coaching session for the current home — the immutable `id` plus its mutable display `name`
/// (nil until it's been titled; the UI supplies a fallback). Backs the Sessions list.
struct SessionInfo: Decodable, Identifiable, Hashable {
    let sessionId: String
    let name: String?
    let updatedAt: Double
    let status: String?            // "active" | "complete" — a concluded session can show as done

    var id: String { sessionId }
    var isComplete: Bool { status == "complete" }
}

/// The `/sessions` payload: every session (newest first) and which one is current.
struct SessionList: Decodable {
    let sessions: [SessionInfo]
    let current: String?
}
