import Foundation

/// Email and password accounts, spoken directly to Supabase Auth over HTTPS.
///
/// No SDK. Auth is four JSON calls, and a dependency would cost more than it
/// saves. Nothing else in Trace touches the network: climbs, clips and wall
/// photos stay on the phone whether or not you have an account.
enum AuthClient {

    // MARK: Configuration

    /// Filled in once a Supabase project exists. Until then the app runs in its
    /// local-only mode and the sign-in screen says so plainly rather than
    /// failing at the user.
    struct Config {
        var url: String
        var anonKey: String

        var isConfigured: Bool {
            !url.isEmpty && !anonKey.isEmpty && url.hasPrefix("https://")
        }
    }

    static var config = Config(
        url: Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "",
        anonKey: Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    )

    static var isConfigured: Bool { config.isConfigured }

    // MARK: Errors

    enum AuthError: LocalizedError, Equatable {
        case notConfigured
        case invalidEmail
        case weakPassword
        case wrongCredentials
        case emailTaken
        case needsConfirmation(String)
        case offline
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Accounts are not switched on yet. You can still use Trace on this phone."
            case .invalidEmail:
                return "That does not look like an email address."
            case .weakPassword:
                return "Use at least 8 characters."
            case .wrongCredentials:
                return "That email and password do not match."
            case .emailTaken:
                return "There is already an account with that email. Try signing in."
            case .needsConfirmation(let email):
                return "Check \(email) for a confirmation link, then sign in."
            case .offline:
                return "No connection. Trace works offline, so you can carry on without signing in."
            case .server(let message):
                return message
            }
        }
    }

    // MARK: Validation
    //
    // Checked before anything is sent, so the common mistakes never cost a round
    // trip and never surface as a server error the climber has to decode.

    static func validateEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5, !trimmed.hasPrefix("@"), !trimmed.hasSuffix("@") else { return false }
        guard let at = trimmed.firstIndex(of: "@"), trimmed.lastIndex(of: "@") == at else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."),
              !domain.contains("..") else { return false }
        return !trimmed.contains(" ")
    }

    static let minimumPasswordLength = 8

    static func validatePassword(_ password: String) -> Bool {
        password.count >= minimumPasswordLength
    }

    // MARK: Calls

    static func signUp(email: String, password: String) async throws -> Session {
        try await authenticate(path: "/auth/v1/signup", email: email, password: password, signingUp: true)
    }

    static func signIn(email: String, password: String) async throws -> Session {
        try await authenticate(path: "/auth/v1/token?grant_type=password",
                               email: email, password: password, signingUp: false)
    }

    /// Sends a reset link. Succeeds silently for unknown addresses, which is
    /// deliberate on Supabase's side: it stops the endpoint confirming who has
    /// an account.
    static func sendPasswordReset(email: String) async throws {
        guard isConfigured else { throw AuthError.notConfigured }
        guard validateEmail(email) else { throw AuthError.invalidEmail }
        _ = try await post(path: "/auth/v1/recover", body: ["email": trimmed(email)], bearer: nil)
    }

    static func signOut(session: Session) async {
        guard isConfigured else { return }
        _ = try? await post(path: "/auth/v1/logout", body: [:], bearer: session.accessToken)
    }

    /// Deletes the account itself, not just this phone's copy of it.
    ///
    /// Apple requires that an app which creates an account can also destroy it
    /// from inside the app, and an account that survives on a server after the
    /// app has said it is gone is a lie whichever way you look at it.
    ///
    /// Supabase's own user-delete endpoint takes a service role key, which
    /// cannot ship in an app: anyone who pulled it out of the binary could
    /// delete anybody. So the account deletes itself through a security-definer
    /// function called with the climber's own token, which is the standard
    /// arrangement and the only one that does not put an administrative key on
    /// a phone. The function has to exist on the project before this can work,
    /// and `Supabase.sql` in the repository is the one to install:
    ///
    ///     create or replace function public.delete_current_user()
    ///     returns void language plpgsql security definer set search_path = '' as $$
    ///     begin delete from auth.users where id = auth.uid(); end; $$;
    ///
    /// Throwing is meaningful. The caller must not wipe the phone if this fails,
    /// because then the account would outlive every record of it and the person
    /// would have no way left to ask for it again.
    static func deleteAccount(session: Session) async throws {
        guard isConfigured else { throw AuthError.notConfigured }
        _ = try await post(path: "/rest/v1/rpc/delete_current_user",
                           body: [:], bearer: session.accessToken)
    }

    static func refresh(session: Session) async throws -> Session {
        guard isConfigured else { throw AuthError.notConfigured }
        let data = try await post(path: "/auth/v1/token?grant_type=refresh_token",
                                  body: ["refresh_token": session.refreshToken], bearer: nil)
        return try parseSession(data)
    }

    // MARK: Plumbing

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func authenticate(path: String, email: String, password: String,
                                     signingUp: Bool) async throws -> Session {
        guard isConfigured else { throw AuthError.notConfigured }
        guard validateEmail(email) else { throw AuthError.invalidEmail }
        guard validatePassword(password) else { throw AuthError.weakPassword }

        let data = try await post(path: path,
                                  body: ["email": trimmed(email), "password": password],
                                  bearer: nil)

        // A sign-up on a project that requires email confirmation returns a user
        // and no session. That is a success, not a failure, and it needs saying.
        if signingUp, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["access_token"] == nil, json["id"] != nil {
            throw AuthError.needsConfirmation(trimmed(email))
        }
        return try parseSession(data)
    }

    private static func post(path: String, body: [String: String], bearer: String?) async throws -> Data {
        guard let url = URL(string: config.url + path) else { throw AuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw mapError(status: status, data: data) }
        return data
    }

    /// Supabase reports failures under several different keys depending on the
    /// endpoint and the version, so all of them are read.
    static func mapError(status: Int, data: Data) -> AuthError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = (json["error_description"] as? String)
            ?? (json["msg"] as? String)
            ?? (json["message"] as? String)
            ?? (json["error"] as? String)
            ?? "Something went wrong. Try again."
        let lower = message.lowercased()

        if lower.contains("already registered") || lower.contains("already been registered")
            || lower.contains("user already exists") { return .emailTaken }
        if lower.contains("invalid login") || lower.contains("invalid credentials")
            || status == 400 && lower.contains("grant") { return .wrongCredentials }
        if lower.contains("password") && lower.contains("least") { return .weakPassword }
        if status == 401 || status == 403 { return .wrongCredentials }
        return .server(message)
    }

    static func parseSession(_ data: Data) throws -> Session {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw AuthError.server("Could not read the response from the server.")
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let user = json["user"] as? [String: Any]
        return Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: (user?["id"] as? String) ?? "",
            email: (user?["email"] as? String) ?? ""
        )
    }
}

/// A signed-in session, stored in the keychain rather than in a plist.
struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String

    /// Refreshed a minute early, so a call never goes out on a token about to die.
    var isExpired: Bool { Date().addingTimeInterval(60) >= expiresAt }
}
