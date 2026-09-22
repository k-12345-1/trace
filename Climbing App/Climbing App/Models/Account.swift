import Foundation

/// Who is using this phone.
///
/// An account is identity, not storage. Signing in proves who you are; it does
/// not move anything off the device. Climbs, clips and wall photos stay local
/// whether you have an account or not, which is what makes filming in a gym full
/// of other people unproblematic.
struct Account: Codable, Equatable {
    /// The Supabase user id, or a locally generated one for an account that
    /// never touched a server.
    var id: String
    var email: String
    var name: String
    var createdAt: Date = Date()

    /// True for a name typed on this phone with no server behind it.
    var isLocalOnly: Bool { email.isEmpty }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        // Fall back to the part of the email before the @, which is usually a name.
        if let at = email.firstIndex(of: "@") { return String(email[..<at]) }
        return "Climber"
    }

    /// One or two letters for the masthead.
    var initials: String {
        let letters = displayName.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
            .prefix(2).compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "C" : letters.joined().uppercased()
    }

    static func local(name: String) -> Account {
        Account(id: UUID().uuidString, email: "", name: name)
    }

    static func signedIn(session: Session, name: String = "") -> Account {
        Account(id: session.userID, email: session.email, name: name)
    }
}
