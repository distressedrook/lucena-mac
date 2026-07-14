import SwiftUI

/// Centralized, localizable copy. No free-floating string literals in views — every piece of
/// visible chrome text traces back to here, typed as `LocalizedStringKey`, nested per screen.
/// (Dynamic content — coach beats, the move list — arrives from the state stream, not here.)
enum Strings {

    enum StudySession {
        static var railStudy: LocalizedStringKey { "Study" }
        static var railMap: LocalizedStringKey { "Map" }
        static var railLibrary: LocalizedStringKey { "Library" }
        static var recentSessions: LocalizedStringKey { "Recent sessions" }
        static var newSession: LocalizedStringKey { "New session" }
        static var retry: LocalizedStringKey { "Retry" }
        static var back: LocalizedStringKey { "Back" }
        static var cancel: LocalizedStringKey { "Cancel" }
        static var variations: LocalizedStringKey { "Variations" }
        static var calculateCarefully: LocalizedStringKey { "Careful — calculate deeply" }
        static var showMeTheTrap: LocalizedStringKey { "Show me the poisoned line" }
        static var coachName: LocalizedStringKey { "Lucena" }
        static var youLabel: LocalizedStringKey { "you" }
        static var tabCoach: LocalizedStringKey { "Coach" }
        static var tabAnalysis: LocalizedStringKey { "Analysis" }
        static var gameWhite: LocalizedStringKey { "White" }
        static var gameBlack: LocalizedStringKey { "Black" }
        static var whiteToMove: LocalizedStringKey { "White to move" }
        static var blackToMove: LocalizedStringKey { "Black to move" }
        static var yourMove: LocalizedStringKey { "Your move" }
        static var checkmate: LocalizedStringKey { "Checkmate" }
        static var stalemate: LocalizedStringKey { "Stalemate" }
        static var noSessions: LocalizedStringKey { "No sessions yet" }
        static var untitledSession: LocalizedStringKey { "Untitled session" }

        enum Menu {
            static var flipBoard: LocalizedStringKey { "Flip board" }
            static var disableEngine: LocalizedStringKey { "Disable engine" }
            static var enableEngine: LocalizedStringKey { "Enable engine" }
        }

        enum Terminal {
            static var statusLive: LocalizedStringKey { "live" }
            static var statusOffline: LocalizedStringKey { "offline" }
        }
    }
}
