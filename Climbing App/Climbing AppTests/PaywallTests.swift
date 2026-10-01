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

    /// A store with nothing in it.
    ///
    /// `Store` is a singleton and suites run alongside each other, so a climb
    /// saved by another test is a climb against this one's allowance. Wiping
    /// first is what makes the counts mean anything.
    private func fresh() async -> Store {
        let store = Store.shared
        try? await store.deleteAccount()
        store.continueLocally(name: "Katie")
        return store
    }

    @Test("A new climber has three goes")
    func threeToStart() async {
        let store = await fresh()
        #expect(Store.freeAnalyses == 3)
        #expect(store.freeAnalysesLeft == 3)
        #expect(!store.needsPro)
    }

    /// Clips and scans draw on the same allowance, because both are Trace
    /// telling you something about your climbing.
    @Test("Clips and scans come out of the same three")
    func clipsAndScansShareTheAllowance() async {
        let store = await fresh()
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
    func theFourthAsks() async {
        let store = await fresh()
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
        let store = await fresh()
        for _ in 0..<Store.freeAnalyses {
            store.save(Fixture.climb(path: Fixture.straightPath(), entropy: 1))
        }
        #expect(store.needsPro)
        try await store.deleteAccount()
        #expect(!store.needsPro)
    }
}

/// The state the Subscribe button reads.
///
/// The purchase on a real phone failed with "The App Store is not reachable"
/// while the phone was plainly online. Two things were wrong and both are here.
/// `Subscription` is a singleton, so its one request for the products went out
/// whenever something first touched it, which on a cold launch is before the
/// network is up, and nothing ever asked again: the store stayed empty for the
/// life of the process. And the paywall drew a live Subscribe button over that
/// empty store, so the only way to discover it was to press the button and be
/// told the purchase had failed, which reads as payment being broken rather
/// than as prices not having loaded.
@Suite("The store's answer", .serialized) @MainActor
struct StoreStateTests {

    /// Nothing has been asked yet, so nothing can be bought yet. This is what
    /// keeps the button from being live over a store that has not answered.
    @Test("Before the store answers there is nothing to buy")
    func nothingToBuyBeforeTheAnswer() {
        let billing = Subscription.shared
        if billing.storeState == .loading { #expect(!billing.canBuy) }
    }

    /// Whatever the answer is, `load` has to produce one. Left on `.loading`
    /// the button spins forever, which is the same dead end wearing a nicer
    /// face than the alert was.
    @Test("Asking always settles the state")
    func loadingAlwaysResolves() async {
        let billing = Subscription.shared
        await billing.load()
        #expect(billing.storeState != .loading,
                "the paywall would spin on its Subscribe button forever")

        // The tests run against Trace.storekit, so the store does answer here
        // and the answer has to be both products: a paywall offering a choice
        // between two plans cannot have only one of them for sale.
        if billing.storeState == .ready {
            for plan in Subscription.Plan.allCases {
                #expect(billing.products[plan] != nil,
                        "\(plan.rawValue) did not load: \(billing.products.keys.map(\.rawValue))")
            }
            #expect(billing.canBuy, "the selected plan has no product behind it")
        }
    }
}

@Suite("Comped accounts")
struct CompedTests {
    @Test func theOwnerIsComped() {
        #expect(Subscription.isComped("knrobinson1023@gmail.com"))
        #expect(Subscription.isComped("  KNRobinson1023@Gmail.com "))
    }
    @Test func everyoneElseIsNot() {
        #expect(!Subscription.isComped("someone@example.com"))
        #expect(!Subscription.isComped(nil))
    }
}
