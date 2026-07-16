import Foundation
import Security

/// The login session — talks to `/auth/*` and holds the bearer token.
///
/// Vocabulary (see LLD.md — three different things): a LOGIN session is an authenticated user (this
/// file). A CHAT session is one coaching conversation, of which a user has many. The ACTIVE CHAT is
/// the one they currently have open. This type only ever deals with the first.
///
/// The token lives in the Keychain, not UserDefaults: it is a credential, and UserDefaults is a plist
/// any process running as the user can read.
@MainActor
@Observable
final class AuthClient {
    enum State: Equatable {
        case unknown        // haven't asked the backend yet
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var email: String?

    private let baseURL: URL
    private nonisolated static let service = "ai.lucena.token"

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// The bearer token, read through a memory cache.
    ///
    /// `nonisolated` because it is read from the socket's background task and from URLSession threads
    /// on every request/reconnect: hopping to the main actor would mean either an `await` those call
    /// sites cannot make, or `MainActor.assumeIsolated`, which TRAPS off-main.
    ///
    /// CACHED because this is the hot path — every REST call and every socket connect asks for it.
    /// Going to the Keychain each time is a syscall per request, and on a build without a stable code
    /// identity (an unsigned dev build) macOS cannot match the item's ACL, so it re-prompts for
    /// access on EVERY read. The Keychain stays the durable store, read once per launch; writes go
    /// through both.
    nonisolated var token: String? { Self.box.value }

    private nonisolated static let box = TokenBox()

    // -- lifecycle ---------------------------------------------------------

    /// Decide whether we need a login at all.
    ///
    /// The backend may not require auth (a local single-user run), so we ASK rather than assume: a
    /// probe that comes back 200 means sign-in would be theatre. Only a 401 means a login is needed.
    func refresh() async {
        var req = URLRequest(url: baseURL.appendingPathComponent("session"))
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else {
            state = .unknown            // backend down: not a credentials problem, don't bounce to login
            return
        }
        state = (http.statusCode == 401) ? .signedOut : .signedIn
    }

    func signIn(email: String, password: String) async throws {
        let tok: String = try await post("auth/login", ["email": email, "password": password])
        Self.box.set(tok)
        self.email = email
        state = .signedIn
    }

    func signUp(email: String, password: String) async throws {
        // The register response is CHECKED, not discarded. `try?` here meant every refusal — taken
        // email, weak password, malformed address — fell through to the sign-in below and came back as
        // "that email and password don't match", which is both wrong and unhelpful. Worse: if the
        // email was taken AND the password happened to match, "Create account" silently signed you
        // into somebody else's account.
        let (data, http): (Data, HTTPURLResponse)
        do { (data, http) = try await postRaw("auth/register", ["email": email, "password": password]) }
        catch { throw AuthError.unreachable }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.message(Self.publicMessage(for: json?["error"] as? String,
                                                       fallback: Strings.Auth.Failure.generic))
        }
        // Register returns a user, not a token — sign in to get one, so a new account lands you
        // straight in the app rather than back at the form you just filled.
        try await signIn(email: email, password: password)
    }

    /// Ends the login session. Returns false if the credential could NOT be removed from the
    /// Keychain — the user is signed out here and server-side, but a relaunch would find the token
    /// again, so a caller should say so rather than report a clean sign-out.
    ///
    /// Note: the stream teardown is NOT done here. It hangs off `state` in LucenaApp, so it covers
    /// this path and `rejected()` alike — see the note there.
    @discardableResult
    func signOut() async -> Bool {
        if let t = token {
            var req = URLRequest(url: baseURL.appendingPathComponent("auth/logout"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)   // best-effort: revoke server-side too
        }
        let cleared = Self.box.set(nil)
        email = nil
        state = .signedOut
        return cleared
    }

    /// Called when a request or socket is refused: the token is dead (expired, revoked, or the
    /// backend turned auth on), so drop it and show the login rather than a frozen board.
    func rejected() {
        Self.box.set(nil)
        email = nil                 // the rail/UI must not keep showing who the dead token belonged to
        state = .signedOut
    }

    // -- http --------------------------------------------------------------

    private func postRaw(_ path: String, _ body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.unreachable }
        return (data, http)
    }

    private func post(_ path: String, _ body: [String: String]) async throws -> String {
        let (data, http): (Data, HTTPURLResponse)
        do { (data, http) = try await postRaw(path, body) } catch { throw AuthError.unreachable }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard http.statusCode == 200, let tok = json?["token"] as? String else {
            // The fallback is GENERIC, not "bad credentials". An unrecognised code is by definition
            // something we do not understand, and asserting it was the password is a guess that sends
            // the user off retyping a password that was never the problem.
            throw AuthError.message(Self.publicMessage(for: json?["error"] as? String,
                                                       fallback: Strings.Auth.Failure.generic))
        }
        return tok
    }

    /// Map a server error CODE to copy we own — never render the server's string.
    ///
    /// This used to pass `json["error"]` straight to the UI, on the theory that the server's message
    /// is more useful than a guess. It is, right up until it isn't: `error` is not a curated field,
    /// so any unhandled exception, validation detail, or driver message on that path renders verbatim
    /// in the login box. An allow-list inverts the default — a code we recognise gets copy we wrote,
    /// and anything else gets the generic failure. New server codes then read as "generic" until
    /// someone adds them here, which is the safe direction to fail.
    private static func publicMessage(for code: String?, fallback: String) -> String {
        switch code {
        case "bad_credentials":   return Strings.Auth.Failure.badCredentials
        case "email_taken":       return Strings.Auth.Failure.emailTaken
        case "weak_password":     return Strings.Auth.Failure.weakPassword
        case "invalid_email":     return Strings.Auth.Failure.invalidEmail
        case "missing_fields":    return Strings.Auth.Failure.missingFields
        default:                  return fallback
        }
    }

    // -- keychain ----------------------------------------------------------

    private nonisolated static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    fileprivate nonisolated static func keychainRead() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns true when the token is durably stored. A false here means this launch keeps working
    /// (the memory cache holds it) but a relaunch will land on the login.
    @discardableResult
    fileprivate nonisolated static func keychainWrite(_ token: String) -> Bool {
        _ = keychainDelete()
        var q = query()
        q[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    /// Returns true when no token remains in the Keychain.
    ///
    /// `errSecItemNotFound` is SUCCESS here and the distinction matters: the goal is "no credential
    /// stored", and there being none to begin with satisfies it. Only a real failure means the token
    /// survived a sign-out — the one case a caller must not paper over, because the UI would say
    /// signed out while the credential comes back on relaunch.
    @discardableResult
    fileprivate nonisolated static func keychainDelete() -> Bool {
        let status = SecItemDelete(query() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// The token, held in memory and backed by the Keychain.
///
/// One Keychain read per launch, not one per request. `@unchecked Sendable` with an explicit lock:
/// it is touched from the main actor (sign in/out) and from background request threads, and the
/// invariant is small enough to hold by hand — a lock around three fields.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var cached: String?

    /// Lazily loads from the Keychain on first read, then serves memory.
    var value: String? {
        lock.lock(); defer { lock.unlock() }
        if !loaded {
            cached = AuthClient.keychainRead()
            loaded = true
        }
        return cached
    }

    /// Write through: memory AND the Keychain, so a relaunch still finds the token and no reader can
    /// see a value that disagrees with what is stored. Returns whether the DURABLE half succeeded —
    /// memory is updated either way, so the caller decides what a storage failure means (for a
    /// sign-out it means the credential is still on disk, which is not a sign-out).
    @discardableResult
    func set(_ token: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        cached = token
        loaded = true
        return token.map { AuthClient.keychainWrite($0) } ?? AuthClient.keychainDelete()
    }
}

enum AuthError: LocalizedError, Equatable {
    case unreachable
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: return Strings.Auth.Failure.unreachable
        case .message(let m): return m
        }
    }
}
