import SwiftUI

/// Centralized, localizable copy. No free-floating string literals in views — every piece of
/// visible chrome text traces back to here, typed as `LocalizedStringKey`, nested per screen.
/// (Dynamic content — coach beats, the move list — arrives from the state stream, not here.)
enum Strings {

    enum Auth {
        static var wordmark: LocalizedStringKey { "Lucena" }
        static var tagline: LocalizedStringKey { "An engine-grounded chess coach." }
        static var email: LocalizedStringKey { "Email" }
        static var password: LocalizedStringKey { "Password" }
        static var signIn: LocalizedStringKey { "Sign in" }
        static var createAccount: LocalizedStringKey { "Create account" }
        static var working: LocalizedStringKey { "…" }
        static var noAccountYet: LocalizedStringKey { "No account yet?" }
        static var createOne: LocalizedStringKey { "Create one" }
        static var haveAnAccount: LocalizedStringKey { "Already have an account?" }
        static var signOut: LocalizedStringKey { "Sign out" }
        // No "Forgot password?": a reset needs a reset-token table AND an email provider to send the
        // link, and there is no email integration in the stack. A link that goes nowhere is worse
        // than no link — see RELEASE_CHECKLIST.md.

        /// Failure copy. Not LocalizedStringKey: these are thrown/returned by AuthClient (a
        /// non-View), and are rendered via Text(verbatim:) alongside the server's own messages.
        enum Failure {
            static let badCredentials = "That email and password don't match."
            static let unreachable = "Can't reach the coach. Is the backend running?"
            static let emailTaken = "That email already has an account."
            static let weakPassword = "That password is too short."
            static let invalidEmail = "That doesn't look like an email address."
            static let missingFields = "Enter an email and a password."
            // The catch-all for a server error code we do not recognise. The server's own `error`
            // string is never rendered: it is not a curated field, so an unhandled exception on that
            // path would print itself into the login box. See AuthClient.publicMessage.
            static let generic = "Something went wrong signing you in. Try again."
            static let signOutFailed = "Couldn't fully sign out — your saved login is still on this Mac."
        }
    }

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
        static var played: LocalizedStringKey { "Played" }
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
        static var drillPuzzle: LocalizedStringKey { "Puzzle" }
        static var drillEndgame: LocalizedStringKey { "Endgame" }
        static var drillMidgame: LocalizedStringKey { "Middlegame" }
        static var drillOpening: LocalizedStringKey { "Opening" }
        static var drillGeneric: LocalizedStringKey { "Drill" }
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
