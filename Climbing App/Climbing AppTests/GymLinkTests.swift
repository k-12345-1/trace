import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Filing a climb at the gym it happened in.
@Suite("Climbs and gyms")
struct GymLinkTests {

    private func climb(_ label: String, gym: UUID? = nil, daysAgo: Double = 0) -> Climb {
        Climb(recordedAt: Date().addingTimeInterval(-daysAgo * 86400),
              videoFilename: "x.mov", label: label,
              metrics: Fixture.metrics(), findings: [], frames: [],
              sent: nil, gymID: gym)
    }

    /// A climb saved before the field existed has no gym, and that has to decode
    /// rather than throw, or a phone full of history stops opening.
    @Test func anOlderClimbDecodesWithNoGym() throws {
        let json = """
        {"id":"\(UUID().uuidString)","recordedAt":"2026-01-02T03:04:05Z",
         "videoFilename":"a.mov","label":"Blue slab","findings":[],"frames":[],
         "metrics":{"entropy":1,"logJerk":5,"pathRatio":1.2,"staticElbowAngle":170,
                    "pauseCount":0,"pauseTotal":0,"footAdjustments":0,
                    "comPath":[],"duration":10,"trackingConfidence":0.9}}
        """
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let decoded = try d.decode(Climb.self, from: Data(json.utf8))
        #expect(decoded.gymID == nil)
        #expect(decoded.label == "Blue slab")
    }

    @Test func aGymIdSurvivesARoundTrip() throws {
        let id = UUID()
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(Climb.self, from: e.encode(climb("x", gym: id)))
        #expect(back.gymID == id)
    }

    /// Answering once applies to the route, not to the one attempt, because
    /// attempts on one route are attempts at one gym.
    @Test func filingOneAttemptFilesTheWholeRoute() {
        let gym = UUID()
        let all = [climb("Blue slab", daysAgo: 2),
                   climb("Blue slab", daysAgo: 1),
                   climb("Yellow arete", daysAgo: 1)]
        let filed = Store.filing(gym, for: all[0], in: all)
        #expect(Store.climbs(filed, in: gym).count == 2)
        #expect(filed.filter { $0.label == "Yellow arete" }.allSatisfy { $0.gymID == nil })
    }

    /// Case and stray whitespace in a label must not split one route in two.
    @Test func theRouteMatchIgnoresCaseAndWhitespace() {
        let gym = UUID()
        let all = [climb("Blue Slab"), climb("  blue slab ")]
        let filed = Store.filing(gym, for: all[0], in: all)
        #expect(Store.climbs(filed, in: gym).count == 2)
    }

    /// An untitled climb has no route to spread across, so it files alone.
    @Test func anUntitledClimbFilesOnlyItself() {
        let gym = UUID()
        let all = [climb(""), climb(""), climb("   ")]
        let filed = Store.filing(gym, for: all[0], in: all)
        #expect(Store.climbs(filed, in: gym).count == 1)
    }

    @Test func unfilingPutsItBack() {
        let gym = UUID()
        let all = [climb("Blue slab", gym: gym)]
        let cleared = Store.filing(nil, for: all[0], in: all)
        #expect(Store.climbs(cleared, in: gym).isEmpty)
    }

    @Test func climbsAtAGymComeBackNewestFirst() {
        let gym = UUID()
        let all = [climb("a", gym: gym, daysAgo: 1),
                   climb("b", gym: gym, daysAgo: 9),
                   climb("c", gym: gym, daysAgo: 4)]
        #expect(Store.climbs(all, in: gym).map(\.label) == ["a", "c", "b"])
    }

    // MARK: The default offered when filming

    @Test func theLikelyGymIsTheLastOneYouUsed() {
        let a = Gym(name: "Gym A"), b = Gym(name: "Gym B")
        #expect(Store.likelyGym(climbs: [], gyms: [a, b]) == nil)
        let history = [climb("old", gym: a.id, daysAgo: 5),
                       climb("new", gym: b.id, daysAgo: 1)]
        #expect(Store.likelyGym(climbs: history, gyms: [a, b])?.id == b.id)
    }

    @Test func oneGymIsItsOwnDefault() {
        let only = Gym(name: "The only one")
        #expect(Store.likelyGym(climbs: [], gyms: [only])?.id == only.id)
    }

    /// A gym that has been deleted must not come back as a default.
    @Test func aDeletedGymIsNotOffered() {
        let gone = Gym(name: "Gone")
        let history = [climb("x", gym: gone.id, daysAgo: 1)]
        #expect(Store.likelyGym(climbs: history, gyms: []) == nil)
    }
}

/// The mark drawn for a gym, which is not a logo.
@Suite("Gym marks")
@MainActor
struct GymMarkTests {

    @Test func theMarkIsStableForAGym() {
        let a = GymMark(name: "Movement Boulder", seed: "n123")
        let b = GymMark(name: "Movement Boulder", seed: "n123")
        #expect(a.tintForTesting == b.tintForTesting)
    }

    @Test func differentGymsCanDiffer() {
        // Not a guarantee for any given pair, but the set must not collapse to one.
        let seeds = ["n1", "n2", "n3", "w4", "w5", "r6", "n77", "n812"]
        let tints = Set(seeds.map { GymMark(name: "X", seed: $0).tintForTesting })
        #expect(tints.count > 1)
    }

    @Test func fillerWordsDoNotBecomeTheMonogram() {
        #expect(GymMark(name: "The Spot Bouldering Gym", seed: "x").initialsForTesting == "SB")
        #expect(GymMark(name: "Berkeley Ironworks", seed: "x").initialsForTesting == "BI")
    }

    @Test func aNameWithNoLettersStillGetsAMark() {
        #expect(GymMark(name: "", seed: "x").initialsForTesting == "G")
        #expect(GymMark(name: "!!!", seed: "x").initialsForTesting == "G")
    }
}

/// Which Explore rows get the check.
@Suite("Explore recognizing your gyms")
struct ExploreMatchTests {
    private func venue(_ id: String, _ name: String) -> Venue {
        Venue(id: id, name: name, city: "Cambridge", state: "MA", street: nil,
              website: nil, latitude: 42.37, longitude: -71.12)
    }
    private let central = [
        ("1", "Central Rock Gym Harvard"), ("2", "Central Rock Gym Cambridge"),
        ("3", "Central Rock Gym Watertown"), ("4", "Boston Bouldering Project")
    ]
    private var venues: [Venue] { central.map { venue($0.0, $0.1) } }

    /// The defect: a gym typed as "Central Rock Gym" lit up every Central Rock.
    @Test func aNameThatFitsSeveralVenuesClaimsNone() {
        let gyms = [Gym(name: "Central Rock Gym")]
        for v in venues {
            #expect(ExploreScreen.mine(v, among: venues, gyms: gyms) == nil, Comment(rawValue: v.name))
        }
    }

    @Test func aNameThatFitsOneVenueClaimsIt() {
        let gyms = [Gym(name: "Central Rock Harvard")]
        #expect(ExploreScreen.mine(venues[0], among: venues, gyms: gyms) != nil)
        #expect(ExploreScreen.mine(venues[1], among: venues, gyms: gyms) == nil)
    }

    @Test func anExactNameAlwaysClaims() {
        let gyms = [Gym(name: "central rock gym cambridge")]
        #expect(ExploreScreen.mine(venues[1], among: venues, gyms: gyms) != nil)
        #expect(ExploreScreen.mine(venues[0], among: venues, gyms: gyms) == nil)
    }

    @Test func aVenueIdBeatsEverything() {
        let gyms = [Gym(name: "Whatever", venueID: "3")]
        #expect(ExploreScreen.mine(venues[2], among: venues, gyms: gyms) != nil)
        #expect(ExploreScreen.mine(venues[0], among: venues, gyms: gyms) == nil)
    }
}
