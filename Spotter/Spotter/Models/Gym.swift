import Foundation
import CoreGraphics

/// A gym you climb at. Created by you, on the spot, with no directory to join
/// and nobody to ask. Spotter has no idea which gyms exist in the world and does
/// not need to.
struct Gym: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt: Date = Date()
}

/// A route scanned off a wall.
///
/// It is a photo, a colour, and the holds Spotter found in that colour. It is not
/// a claim about what the setter intended, which is why the climber confirms the
/// holds before it is saved.
struct Route: Codable, Identifiable, Hashable {
    var id = UUID()
    var gymID: UUID
    var name: String
    var grade: String
    var colorHex: String
    var photoFilename: String
    /// Normalised bounding boxes, origin top left.
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
