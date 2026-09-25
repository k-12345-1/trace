import Foundation
import CoreLocation

/// Where the phone is, for the one purpose of putting nearby gyms first.
///
/// Nothing here is stored and nothing is sent. The coordinate is held in memory
/// for as long as the screen is open, used to sort a list that is already on the
/// device, and forgotten. That is why this asks for when-in-use rather than
/// always, and why it stops the moment it has one fix.
@MainActor
final class Whereabouts: NSObject, ObservableObject {

    enum State: Equatable {
        case unasked
        case asking
        case denied
        case failed
        case located(CLLocation)

        var location: CLLocation? {
            if case .located(let l) = self { return l }
            return nil
        }
    }

    @Published private(set) var state: State = .unasked
    /// "Boulder, CO", once a fix has been turned into a name. Nil until then,
    /// and nil if the lookup fails, which is not worth telling anyone about.
    @Published private(set) var placeName: String?

    private let manager = CLLocationManager()
    private let namer = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        // A gym is not a turn to miss. Coarse accuracy is plenty for sorting a
        // list by city, and it is the setting that asks least of the person.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        adopt(manager.authorizationStatus)
    }

    /// Asks, or uses what has already been granted.
    func find() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .asking
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            state = .asking
            manager.requestLocation()
        }
    }

    /// The city the fix is in, for showing rather than for sorting. The sort
    /// uses the coordinate directly and never needs this.
    private func name(_ fix: CLLocation) async {
        guard let mark = try? await namer.reverseGeocodeLocation(fix).first else { return }
        let city = mark.locality ?? mark.subAdministrativeArea
        let region = mark.administrativeArea
        switch (city, region) {
        case let (c?, r?): placeName = "\(c), \(r)"
        case let (c?, nil): placeName = c
        case let (nil, r?): placeName = r
        default: placeName = nil
        }
    }

    private func adopt(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:            state = .unasked
        case .denied, .restricted:      state = .denied
        default:                        break
        }
    }
}

extension Whereabouts: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.state = .asking
                manager.requestLocation()
            case .denied, .restricted:
                self.state = .denied
            default:
                self.state = .unasked
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in
            self.state = .located(fix)
            await self.name(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            // A denial arrives here too on some paths; keep that distinct from a
            // fix that simply could not be got.
            if (error as? CLError)?.code == .denied {
                self.state = .denied
            } else if self.state.location == nil {
                self.state = .failed
            }
        }
    }
}
