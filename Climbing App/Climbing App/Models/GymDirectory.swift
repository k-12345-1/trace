import Foundation
import CoreLocation

/// A climbing gym in the United States, as a place rather than as something you
/// have scanned.
///
/// This is the opposite of `Gym`, which only exists because you scanned a route
/// at it. A `Venue` is a gym that exists whether or not you have ever been.
struct Venue: Identifiable, Hashable {
    let name: String
    let city: String
    let state: String
    /// The city, not the street. See the note on `GymDirectory`.
    let latitude: Double
    let longitude: Double

    var id: String { "\(name)|\(city)|\(state)" }
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

/// The gyms Trace knows about.
///
/// Two things have to be said plainly about this list, because the screen that
/// shows it would otherwise imply more than it has.
///
/// The coordinates are **city centers, not street addresses**. A gym's distance
/// is therefore the distance to its city, which is the right precision for
/// "what is near me" and the wrong precision for "how far is the door". The
/// screen says so rather than rounding the problem away.
///
/// And this is a hand-built starter list, not a survey. It covers the larger
/// metros and the chains, it is certainly missing gyms, and nothing here has
/// been checked against a live source. It exists so the screen has something
/// real to show; it is not a product claim about coverage.
enum GymDirectory {

    static let all: [Venue] = [
        // Northeast
        Venue(name: "Brooklyn Boulders Gowanus", city: "Brooklyn", state: "NY", latitude: 40.6782, longitude: -73.9442),
        Venue(name: "The Cliffs at LIC", city: "Long Island City", state: "NY", latitude: 40.7447, longitude: -73.9485),
        Venue(name: "The Cliffs at Harlem", city: "New York", state: "NY", latitude: 40.8116, longitude: -73.9465),
        Venue(name: "VITAL Brooklyn", city: "Brooklyn", state: "NY", latitude: 40.6782, longitude: -73.9442),
        Venue(name: "Central Rock Gym Watertown", city: "Watertown", state: "MA", latitude: 42.3709, longitude: -71.1828),
        Venue(name: "Central Rock Gym Cambridge", city: "Cambridge", state: "MA", latitude: 42.3736, longitude: -71.1097),
        Venue(name: "MetroRock Everett", city: "Everett", state: "MA", latitude: 42.4084, longitude: -71.0537),
        Venue(name: "Rock Spot Climbing South Boston", city: "Boston", state: "MA", latitude: 42.3601, longitude: -71.0589),
        Venue(name: "Gravity Vault Hoboken", city: "Hoboken", state: "NJ", latitude: 40.7440, longitude: -74.0324),
        Venue(name: "Philadelphia Rock Gym Oaks", city: "Oaks", state: "PA", latitude: 40.1298, longitude: -75.4610),
        Venue(name: "Ascend Pittsburgh", city: "Pittsburgh", state: "PA", latitude: 40.4406, longitude: -79.9959),
        Venue(name: "Earth Treks Crystal City", city: "Arlington", state: "VA", latitude: 38.8816, longitude: -77.0910),
        Venue(name: "Earth Treks Columbia", city: "Columbia", state: "MD", latitude: 39.2037, longitude: -76.8610),
        Venue(name: "Movement Timonium", city: "Timonium", state: "MD", latitude: 39.4390, longitude: -76.6091),

        // Southeast
        Venue(name: "Stone Summit Midtown", city: "Atlanta", state: "GA", latitude: 33.7490, longitude: -84.3880),
        Venue(name: "Stone Summit Kennesaw", city: "Kennesaw", state: "GA", latitude: 34.0234, longitude: -84.6155),
        Venue(name: "Inner Peaks Charlotte", city: "Charlotte", state: "NC", latitude: 35.2271, longitude: -80.8431),
        Venue(name: "Triangle Rock Club Raleigh", city: "Raleigh", state: "NC", latitude: 35.7796, longitude: -78.6382),
        Venue(name: "Aiguille Rock Climbing Center", city: "Longwood", state: "FL", latitude: 28.7031, longitude: -81.3384),
        Venue(name: "Vertical Ventures Tampa", city: "Tampa", state: "FL", latitude: 27.9506, longitude: -82.4572),
        Venue(name: "High Point Climbing Chattanooga", city: "Chattanooga", state: "TN", latitude: 35.0456, longitude: -85.3097),
        Venue(name: "Climb Nashville West", city: "Nashville", state: "TN", latitude: 36.1627, longitude: -86.7816),

        // Midwest
        Venue(name: "First Ascent Avondale", city: "Chicago", state: "IL", latitude: 41.8781, longitude: -87.6298),
        Venue(name: "Movement Wrigleyville", city: "Chicago", state: "IL", latitude: 41.9484, longitude: -87.6553),
        Venue(name: "Upper Limits St. Louis", city: "St. Louis", state: "MO", latitude: 38.6270, longitude: -90.1994),
        Venue(name: "Vertical Endeavors Minneapolis", city: "Minneapolis", state: "MN", latitude: 44.9778, longitude: -93.2650),
        Venue(name: "Minneapolis Bouldering Project", city: "Minneapolis", state: "MN", latitude: 44.9778, longitude: -93.2650),
        Venue(name: "Hoosier Heights Indianapolis", city: "Indianapolis", state: "IN", latitude: 39.7684, longitude: -86.1581),
        Venue(name: "Sharon Woods Climbing Cincinnati", city: "Cincinnati", state: "OH", latitude: 39.1031, longitude: -84.5120),
        Venue(name: "Adrenaline Climbing Columbus", city: "Columbus", state: "OH", latitude: 39.9612, longitude: -82.9988),
        Venue(name: "Planet Rock Madison Heights", city: "Madison Heights", state: "MI", latitude: 42.4859, longitude: -83.1052),
        Venue(name: "Boulders Climbing Gym Madison", city: "Madison", state: "WI", latitude: 43.0731, longitude: -89.4012),

        // Mountain West
        Venue(name: "Movement Boulder", city: "Boulder", state: "CO", latitude: 40.0150, longitude: -105.2705),
        Venue(name: "Movement RiNo", city: "Denver", state: "CO", latitude: 39.7392, longitude: -104.9903),
        Venue(name: "Movement Englewood", city: "Englewood", state: "CO", latitude: 39.6478, longitude: -104.9878),
        Venue(name: "The Spot Bouldering Gym", city: "Boulder", state: "CO", latitude: 40.0150, longitude: -105.2705),
        Venue(name: "Momentum Millcreek", city: "Salt Lake City", state: "UT", latitude: 40.7608, longitude: -111.8910),
        Venue(name: "The Front Climbing Club SLC", city: "Salt Lake City", state: "UT", latitude: 40.7608, longitude: -111.8910),
        Venue(name: "Momentum Silver Street", city: "Lehi", state: "UT", latitude: 40.3916, longitude: -111.8508),
        Venue(name: "Blocfit Bouldering Boise", city: "Boise", state: "ID", latitude: 43.6150, longitude: -116.2023),
        Venue(name: "Spire Climbing Center", city: "Bozeman", state: "MT", latitude: 45.6770, longitude: -111.0429),
        Venue(name: "Session Climbing Santa Fe", city: "Santa Fe", state: "NM", latitude: 35.6870, longitude: -105.9378),
        Venue(name: "Focus Climbing Center", city: "Mesa", state: "AZ", latitude: 33.4152, longitude: -111.8315),
        Venue(name: "Phoenix Rock Gym", city: "Tempe", state: "AZ", latitude: 33.4255, longitude: -111.9400),

        // Texas
        Venue(name: "Austin Bouldering Project", city: "Austin", state: "TX", latitude: 30.2672, longitude: -97.7431),
        Venue(name: "Crux Climbing Center", city: "Austin", state: "TX", latitude: 30.2672, longitude: -97.7431),
        Venue(name: "Summit Climbing Dallas", city: "Dallas", state: "TX", latitude: 32.7767, longitude: -96.7970),
        Venue(name: "Momentum Katy", city: "Katy", state: "TX", latitude: 29.7858, longitude: -95.8245),
        Venue(name: "Texas Rock Gym Houston", city: "Houston", state: "TX", latitude: 29.7604, longitude: -95.3698),

        // West Coast
        Venue(name: "Movement Dogpatch", city: "San Francisco", state: "CA", latitude: 37.7749, longitude: -122.4194),
        Venue(name: "Movement Mission Cliffs", city: "San Francisco", state: "CA", latitude: 37.7749, longitude: -122.4194),
        Venue(name: "Berkeley Ironworks", city: "Berkeley", state: "CA", latitude: 37.8715, longitude: -122.2730),
        Venue(name: "Diablo Rock Gym", city: "Concord", state: "CA", latitude: 37.9779, longitude: -122.0311),
        Venue(name: "Sender One LAX", city: "Los Angeles", state: "CA", latitude: 34.0522, longitude: -118.2437),
        Venue(name: "Sender One Santa Ana", city: "Santa Ana", state: "CA", latitude: 33.7455, longitude: -117.8677),
        Venue(name: "Touchstone LA Boulders", city: "Los Angeles", state: "CA", latitude: 34.0522, longitude: -118.2437),
        Venue(name: "Mesa Rim San Diego", city: "San Diego", state: "CA", latitude: 32.7157, longitude: -117.1611),
        Venue(name: "Movement Sunnyvale", city: "Sunnyvale", state: "CA", latitude: 37.3688, longitude: -122.0363),
        Venue(name: "Seattle Bouldering Project", city: "Seattle", state: "WA", latitude: 47.6062, longitude: -122.3321),
        Venue(name: "Vertical World Seattle", city: "Seattle", state: "WA", latitude: 47.6062, longitude: -122.3321),
        Venue(name: "Portland Rock Gym", city: "Portland", state: "OR", latitude: 45.5152, longitude: -122.6784),
        Venue(name: "The Circuit Bouldering Gym", city: "Portland", state: "OR", latitude: 45.5152, longitude: -122.6784),
        Venue(name: "Alaska Rock Gym", city: "Anchorage", state: "AK", latitude: 61.2181, longitude: -149.9003),
        Venue(name: "Volcanic Rock Gym", city: "Kailua", state: "HI", latitude: 21.4022, longitude: -157.7394)
    ]

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
