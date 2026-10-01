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
    /// A picture for this gym, stored on the phone.
    ///
    /// Yours, not ours. Trace ships no gym logos: they are trademarks, there is
    /// no licensed source for six hundred of them, and fetching each from its
    /// own website would tell six hundred servers that someone opened this app.
    /// What it can do is let you put one there, which is a photograph of the
    /// place or their sign or whatever you like, and it never leaves the phone.
    var imageFilename: String? = nil

    var imageURL: URL? {
        imageFilename.map { Store.gymImagesDirectory.appendingPathComponent($0) }
    }
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
    /// One outline per hold, normalised, in the holds' order. Nil on routes
    /// scanned before outlines existed, which then draw boxes; an empty
    /// outline draws a box for that hold alone.
    var outlines: [[CGPoint]]? = nil
    /// The edges the route probably continues past, as read when it was
    /// scanned. Nil on routes scanned before this was read; empty when the
    /// scan looked whole.
    var continues: [CoverageEngine.Edge]? = nil

    /// The outline for a hold, when there is one worth drawing.
    func outline(at i: Int) -> [CGPoint]? {
        guard let outlines, outlines.count == holds.count, outlines[i].count >= 3 else { return nil }
        return outlines[i]
    }

    var photoURL: URL { Store.routePhotosDirectory.appendingPathComponent(photoFilename) }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled route" : name
    }
}
