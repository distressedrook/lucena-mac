import Foundation

/// Display model for the MARGIN — JSON-inspection mode (owner, 2026-07-23).
/// The struct mirrors the /margin wire EXACTLY — nothing more: the stage
/// label, the pretty-printed pre/post-verify sheet JSON, and the polling
/// flag. The former card model (epigraph/theory/cards/urgent) lives in git
/// history alongside the backend's card builder (backend fb4b2d7).
struct MarginContent: Decodable {
    var statusLine: String?             // "ROLLING…" · "PRE-VERIFY · VERIFYING…" · "POST-VERIFY"
    var raw: String?                    // the pretty-printed sheet JSON — the whole body
    var plansPending: Bool = false      // the verify gate is still running — poll

    private enum CodingKeys: String, CodingKey { case statusLine, raw, plansPending }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusLine = try c.decodeIfPresent(String.self, forKey: .statusLine)
        raw = try c.decodeIfPresent(String.self, forKey: .raw)
        plansPending = try c.decodeIfPresent(Bool.self, forKey: .plansPending) ?? false
    }

    init(statusLine: String? = nil, raw: String? = nil, plansPending: Bool = false) {
        self.statusLine = statusLine
        self.raw = raw
        self.plansPending = plansPending
    }
}
