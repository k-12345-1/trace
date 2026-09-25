import Foundation
import CoreGraphics

/// A gym you climb at. Still created by you, on the spot: you can type a name
/// that is in no directory anywhere and Trace will take it.
struct Gym: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt: Date = Date()
    /// Set when this gym was added by tapping it in Explore, so that screen can
    /// recognize it later without guessing from the name. Nil for a gym you
    /// typed, and nil for every gym saved before Explore could add them, which
    /// decodes cleanly because it is optional.
    var venueID: String? = nil
}

/// A route scanned off a wall.
///
/// It is a photo, a color, and the holds Trace found in that color. It is not
/// a claim about what the setter intended, which is why the climber confirms the
/// holds before it is saved.
struct Route: Codable, Identifiable, Hashable {
    var id = UUID()
    var gymID: UUID
    var name: String
    var grade: String
    var colorHex: String
    var photoFilename: String
    /// Normalized bounding boxes, origin top left.
    var holds: [CGRect]
    var scannedAt: Date = Date()
    var sent: Bool = false
    /// Free text, kept so a scanned route can be matched to climbs logged by label.
    var note: String = ""

    var photoURL: URL { Store.routePhotosDirectory.appendingPathComponent(photoFilename) }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled route" : name
    }
}
