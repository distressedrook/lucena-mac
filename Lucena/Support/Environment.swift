import SwiftUI

// Shared services are injected read-only through the environment (one `@Entry` per service,
// nil-defaulted so previews/tests can omit or stub them). Set once at the app root; views read
// them via `@Environment(\.stateStream)` / `\.coachBridge`.
extension EnvironmentValues {
    @Entry var stateStream: StateStream? = nil
    @Entry var coachBridge: CoachBridge? = nil
    @Entry var lucenaHome: URL? = nil
}
