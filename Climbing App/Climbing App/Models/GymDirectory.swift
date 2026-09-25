import Foundation
import CoreLocation

/// A climbing gym in the United States, as a place rather than as something you
/// have scanned.
///
/// This is the opposite of `Gym`, which only exists because you put it there. A
/// `Venue` is a gym that exists whether or not you have ever been.
struct Venue: Identifiable, Hashable, Decodable {
    /// The OpenStreetMap id it came from, which is stable across rebuilds of
    /// the directory in a way that a name or a position is not.
    let id: String
    let name: String
    let city: String
    let state: String
    /// The building, not the city. Absent where OpenStreetMap has no address
    /// for it, which is why it is optional rather than a guess.
    let street: String?
    let website: String?
    let latitude: Double
    let longitude: Double

    var place: String { "\(city), \(state)" }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Miles from a point, as the crow flies.
    func miles(from location: CLLocation) -> Double {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        return location.distance(from: here) / 1609.344
    }
}

/// Every indoor climbing gym in the United States that OpenStreetMap knows about.
///
/// Where the data comes from, because it changes what the numbers mean.
///
/// This is built from OpenStreetMap, filtered to indoor facilities and reverse
/// geocoded against the US Census Bureau for city and state. The coordinates are
/// the buildings themselves, so a distance is to the gym and not, as it was in
/// the hand written list this replaces, to the middle of its city.
///
/// OpenStreetMap is made by volunteers, which is the reason it can be used at
/// all and also the reason it is uneven. A gym that nobody has mapped is not
/// here. A gym that closed last month may still be. It is a real survey rather
/// than a list somebody typed out, and it is not a guarantee.
///
/// The data is under the Open Database License, which requires the credit shown
/// at the bottom of the Explore screen. Do not remove it.
enum GymDirectory {

    /// Loaded once, from the bundle.
    static let all: [Venue] = {
        guard let url = Bundle.main.url(forResource: "gyms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let venues = try? JSONDecoder().decode([Venue].self, from: data)
        else { return [] }
        return venues
    }()

    /// When the snapshot was taken. Shown rather than hidden, because a
    /// directory with no date on it invites you to trust it more than you should.
    static let captured = "September 2026"

    /// The whole list, nearest first.
    static func sorted(by location: CLLocation?) -> [Venue] {
        guard let location else {
            return all.sorted { ($0.state, $0.city, $0.name) < ($1.state, $1.city, $1.name) }
        }
        return all.sorted { $0.miles(from: location) < $1.miles(from: location) }
    }

    /// Grouped by state, for browsing when there is no location to sort by.
    static var byState: [(state: String, venues: [Venue])] {
        Dictionary(grouping: all, by: \.state)
            .map { (state: $0.key, venues: $0.value.sorted { $0.city < $1.city }) }
            .sorted { $0.state < $1.state }
    }
}
