import Testing
import Foundation
import CoreLocation
@testable import ClimbingApp

/// The gym directory is data rather than code, so what is worth pinning is the
/// shape of the data and the fact that it shipped at all.
///
/// A directory that silently fails to load looks, on the screen, exactly like a
/// directory with nothing near you in it. That is the failure these guard.
@Suite("Gym directory")
struct GymDirectoryTests {

    @Test func theDirectoryShipped() {
        // Not merely non-empty. A resource that failed to bundle decodes to an
        // empty array, and so does a one line file, so the floor is set where
        // only the real thing clears it.
        #expect(GymDirectory.all.count > 500)
    }

    @Test func everyVenueIsUsable() {
        for v in GymDirectory.all {
            #expect(!v.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!v.city.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(v.state.count == 2, "\(v.name) has state \"\(v.state)\"")
            #expect(v.state == v.state.uppercased())
        }
    }

    @Test func everyVenueIsInTheUnitedStates() {
        // The continental box plus Alaska and Hawaii. A coordinate that fell
        // outside this would be a geocoding error that the screen would render
        // as a gym thousands of miles away.
        for v in GymDirectory.all {
            let continental = (24.0...49.6).contains(v.latitude)
                && (-125.1...(-66.8)).contains(v.longitude)
            let alaska = (51.0...71.6).contains(v.latitude)
                && (-180.0...(-129.0)).contains(v.longitude)
            let hawaii = (18.8...22.4).contains(v.latitude)
                && (-160.4...(-154.7)).contains(v.longitude)
            #expect(continental || alaska || hawaii,
                    "\(v.name) sits at \(v.latitude), \(v.longitude)")
        }
    }

    @Test func idsAreUnique() {
        let ids = Set(GymDirectory.all.map(\.id))
        #expect(ids.count == GymDirectory.all.count)
    }

    @Test func nearestComesFirst() {
        // Boulder, Colorado. Whatever the nearest gym to it turns out to be, it
        // has to be nearer than the last one in the list.
        let here = CLLocation(latitude: 40.0150, longitude: -105.2705)
        let sorted = GymDirectory.sorted(by: here)
        #expect(sorted.count == GymDirectory.all.count)
        guard let first = sorted.first, let last = sorted.last else {
            Issue.record("the directory is empty"); return
        }
        #expect(first.miles(from: here) <= last.miles(from: here))
        #expect(first.miles(from: here) < 30)
    }

    @Test func withoutALocationItIsAlphabeticalByState() {
        let sorted = GymDirectory.sorted(by: nil)
        let states = sorted.map(\.state)
        #expect(states == states.sorted())
    }

    @Test func everyStateGroupHoldsOnlyItsOwn() {
        for group in GymDirectory.byState {
            #expect(group.venues.allSatisfy { $0.state == group.state })
        }
    }
}
