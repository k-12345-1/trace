import Foundation

/// The way into Trace while there is no authentication server.
///
/// An account is required to use the app, and nothing yet issues one, so
/// without this the app is unreachable on a fresh install. These credentials
/// sign in locally: no request is made, no password is checked against anything,
/// and the account that results is marked local.
///
/// It is deliberately not a back door around a real account. The moment
/// `AuthClient.isConfigured` is true, these credentials are still accepted, but
/// the screen stops advertising them, and a demo account can be signed out of
/// like any other.
enum DemoAccount {
    static let email = "demo@traceclimb.co"
    static let password = "climbon"
    static let name = "Demo climber"

    /// Whether the pair typed into the form is the demo pair. Case and
    /// surrounding whitespace are forgiven, because a demo nobody can type in is
    /// not a demo.
    static func matches(email typed: String, password: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(email) == .orderedSame
        && password == Self.password
    }
}
