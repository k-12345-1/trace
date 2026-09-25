import SwiftUI
import UIKit

/// Gym logos, fetched once and then kept on the phone.
///
/// A list of six hundred gyms drawn as six hundred pairs of initials tells you
/// nothing you did not already know from the name beside them. A logo is the
/// thing that makes a row recognizable before you read it, and the only place a
/// gym's logo exists is on the gym's own website.
///
/// The cost is honest and it is the reason this is a setting: asking a gym's
/// site for its icon tells that site somebody is interested in that gym. So
/// nothing goes with the request except the request, it happens once per gym
/// ever, the answer lives on the phone afterwards, and the privacy policy says
/// so. Turning the setting off stops it and leaves the logos already saved
/// where they are.
///
/// Only for gyms actually on screen. Scrolling past a row is what asks for it,
/// which means a directory of six hundred gyms makes a handful of requests
/// rather than six hundred.
@MainActor
final class VenueLogos: ObservableObject {

    static let shared = VenueLogos()

    /// Bumped when a logo arrives, so the rows waiting on one redraw.
    @Published private(set) var version = 0

    private var images: [String: UIImage] = [:]
    /// Asked and answered, either way. A gym whose site has no usable icon is
    /// remembered as such, or every launch would ask it again forever.
    private var settled: Set<String> = []
    private var inFlight: Set<String> = []

    /// Few enough that a scroll does not open thirty sockets at once.
    private let atOnce = 4

    private init() { loadMisses() }

    // MARK: Where they live

    private static var directory: URL {
        let url = Store.documents.appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var missesURL: URL {
        directory.appendingPathComponent("none.json")
    }

    private static func file(_ id: String) -> URL {
        // An OpenStreetMap id is "node/123456", and a slash in a filename is a
        // directory that does not exist.
        directory.appendingPathComponent(id.replacingOccurrences(of: "/", with: "-") + ".img")
    }

    // MARK: Asking

    /// The logo for a gym, and a request for it if this is the first time.
    ///
    /// Returns nil until one arrives, which is what the monogram is for: a row
    /// is never empty while it waits, and most rows wait forever because most
    /// gyms have no usable icon.
    func logo(for venue: Venue) -> UIImage? {
        if let hit = images[venue.id] { return hit }
        guard Store.shared.fetchesGymLogos else { return nil }
        guard !settled.contains(venue.id), !inFlight.contains(venue.id) else { return nil }

        // On disk from a previous run.
        if let data = try? Data(contentsOf: Self.file(venue.id)),
           let image = UIImage(data: data) {
            images[venue.id] = image
            return image
        }
        guard venue.website != nil, inFlight.count < atOnce else { return nil }

        inFlight.insert(venue.id)
        Task { await fetch(venue) }
        return nil
    }

    /// The same, for a gym in your list that came out of the directory. A gym
    /// you typed yourself has no venue behind it and no site to ask.
    func logo(for gym: Gym) -> UIImage? {
        guard let id = gym.venueID,
              let venue = GymDirectory.all.first(where: { $0.id == id })
        else { return nil }
        return logo(for: venue)
    }

    private func fetch(_ venue: Venue) async {
        defer { inFlight.remove(venue.id) }
        guard let data = try? await LogoFetcher.logo(for: venue),
              let image = UIImage(data: data) else {
            settled.insert(venue.id)
            saveMisses()
            return
        }
        try? data.write(to: Self.file(venue.id), options: .atomic)
        images[venue.id] = image
        version += 1
    }

    // MARK: The ones that had nothing

    private func loadMisses() {
        guard let data = try? Data(contentsOf: Self.missesURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
        settled = Set(ids)
    }

    private func saveMisses() {
        guard let data = try? JSONEncoder().encode(Array(settled)) else { return }
        try? data.write(to: Self.missesURL, options: .atomic)
    }

    /// Everything fetched, gone. The setting turning off does not do this: a
    /// logo already on the phone costs nothing to keep, and deleting it would
    /// only mean asking again if the setting came back on.
    func forgetEverything() {
        images.removeAll()
        settled.removeAll()
        try? FileManager.default.removeItem(at: Self.directory)
        version += 1
    }
}
