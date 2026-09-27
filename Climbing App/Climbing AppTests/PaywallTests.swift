import Testing
import Foundation
@testable import ClimbingApp

private final class BundleToken {}

/// Three free goes, then Trace asks.
///
/// The free tier used to be one route scan, which let somebody see the scanner
/// work once and never see what the app is for. Three is enough to record a
/// climb, import another, and compare two attempts at the same problem, which
/// is the thing Trace actually does. They are spent on anything that produces
/// feedback: a clip recorded, a clip imported, a wall scanned.
@Suite("The free tier", .serialized) @MainActor
struct PaywallTests {

    private func fresh() -> Store {
        let store = Store.shared
        store.continueLocally(name: "Katie")
        return store
    }

    @Test("A new climber has three goes")
    func threeToStart() {
        let store = fresh()
        #expect(Store.freeAnalyses == 3)
        #expect(store.freeAnalysesLeft == 3)
        #expect(!store.needsPro)
    }

    /// Clips and scans draw on the same allowance, because both are Trace
    /// telling you something about your climbing.
    @Test("Clips and scans come out of the same three")
    func clipsAndScansShareTheAllowance() {
        let store = fresh()
        let before = store.analysesUsed

        store.save(Fixture.climb(path: Fixture.straightPath(), entropy: 1))
        #expect(store.analysesUsed == before + 1)

        let gym = Gym(name: "Brooklyn Boulders")
        store.save(Route(gymID: gym.id, name: "Blue slab", grade: "V2",
                         colorHex: "#2E6BE6", photoFilename: "x.jpg",
                         holds: [.init(x: 0.4, y: 0.5, width: 0.05, height: 0.05),
                                 .init(x: 0.5, y: 0.4, width: 0.05, height: 0.05),
                                 .init(x: 0.45, y: 0.3, width: 0.05, height: 0.05)]))
        #expect(store.analysesUsed == before + 2)
        #expect(store.freeAnalysesLeft == 1)
        #expect(!store.needsPro, "asked before the three were spent")
    }

    @Test("The fourth is where it asks")
    func theFourthAsks() {
        let store = fresh()
        for _ in 0..<Store.freeAnalyses {
            store.save(Fixture.climb(path: Fixture.straightPath(), entropy: 1))
        }
        #expect(store.freeAnalysesLeft == 0)
        #expect(store.needsPro)
        // The scanner asks the same question, so one answer covers both.
        #expect(store.scanNeedsPro)
    }

    /// Deleting everything is not a way to get three more without paying, but
    /// it does reset a phone that has been handed to somebody else, which is
    /// what the delete is for.
    @Test("Deleting the account clears the count")
    func deletingClearsIt() async throws {
        let store = fresh()
        for _ in 0..<Store.freeAnalyses {
            store.save(Fixture.climb(path: Fixture.straightPath(), entropy: 1))
        }
        #expect(store.needsPro)
        try await store.deleteAccount()
        #expect(!store.needsPro)
    }
}
