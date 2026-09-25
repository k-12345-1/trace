import Foundation

/// The way into Trace while there is no authentication server.
///
/// An account is required to use the app, and nothing yet issues one, so
/// without this the app is unreachable on a fresh install. These credentials
/// sign in locally: no request is made, no password is checked against anything,
/// and the account that results is marked local.
///
/// It is deliberately not a back door around a real account. A demo account can
/// be signed out of like any other, and it will keep working unchanged once a
/// real server exists.
///
/// The sign-in screen does not name these any more. They are typed in like any
/// other credentials, which is what makes the screen an honest rehearsal of the
/// real thing rather than a screen with a shortcut on it.
enum DemoAccount {
    static let email = "trace@climb.co"
    static let password = "ClimbOn!"
    static let name = "Demo climber"

    /// Whether the pair typed into the form is the demo pair.
    ///
    /// The address forgives case and stray whitespace, which is what every
    /// sign-in form does and what iOS autocapitalization makes necessary. The
    /// password does not, because a password that forgives case is not a
    /// rehearsal of a real one.
    static func matches(email typed: String, password: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(email) == .orderedSame
        && password == Self.password
    }
}
