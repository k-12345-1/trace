import Foundation

/// What `Store` needs that the seeder cannot have.
///
/// `Store.swift` is compiled into the command line seeder so the seeded files
/// are written by the same code the app reads them with, rather than by a
/// second implementation that can drift. The real `Thumbnails` is UIKit, and
/// the seeder is a macOS tool, so this stands in for it. Nothing here is ever
/// called: the seeder only writes, and every one of these is on a delete path.
enum Thumbnails {
    static var directory: URL {
        Store.documents.appendingPathComponent("Thumbs", isDirectory: true)
    }
    static func remove(for climb: Climb) {}
}

/// Likewise `VenueLogos`, which holds UIImages and belongs to the app.
/// `Store.deleteAccount` clears it, and the seeder never deletes anything.
final class VenueLogos {
    static let shared = VenueLogos()
    func forgetEverything() {}
}
