import Testing
@testable import ClimbingApp

/// What App Review checks on the screen that sells a subscription.
///
/// Guideline 3.1.2(c) wants the title of the auto-renewing subscription, its
/// length, its price, and working links to the privacy policy and the terms.
/// The app was rejected on 2026-10-05 partly for this, so the parts that are
/// ours to get right are held here.
@Suite("Subscription metadata")
struct SubscriptionMetadataTests {

    @Test("Each plan names the subscription, not just how often it bills")
    func planNamesTheSubscription() {
        for plan in Subscription.Plan.allCases {
            #expect(plan.title.contains("Trace Pro"), "\(plan.rawValue) is titled \(plan.title)")
        }
        #expect(Subscription.Plan.yearly.title.contains("yearly"))
        #expect(Subscription.Plan.monthly.title.contains("monthly"))
    }

    /// The identifiers the binary asks the App Store for. These have to match
    /// the products in App Store Connect exactly, or the store answers with
    /// nothing and the paywall has no prices to show.
    @Test("The product identifiers are the ones App Store Connect carries")
    @MainActor
    func productIdentifiers() {
        #expect(Subscription.productIDs.sorted() ==
                ["co.traceclimb.pro.monthly", "co.traceclimb.pro.yearly"])
    }

    /// A price is shown whether or not the store answered, so the screen is
    /// never a subscription offer with no price on it.
    @Test("There is a price and a period even before the store answers")
    @MainActor
    func priceWithoutTheStore() {
        let billing = Subscription.shared
        for plan in Subscription.Plan.allCases {
            #expect(!billing.price(plan).isEmpty)
            #expect(billing.price(plan).contains("$"))
            #expect(["year", "month"].contains(billing.period(plan)))
        }
    }

    /// Nobody is Pro without either paying or being on the comp list, and the
    /// comp list must never be handed to App Review: a comped account is Pro
    /// without StoreKit ever being asked, so the reviewer would never see a
    /// purchase.
    @Test("Comps are a closed list")
    func compsAreClosed() {
        #expect(!Subscription.isComped(nil))
        #expect(!Subscription.isComped("reviewer@apple.com"))
        #expect(!Subscription.isComped(""))
    }
}

/// What the app promises the free plan is, in the three places it says so.
///
/// App Review checks that a subscription's description matches what the app
/// actually does. The Subscription screen used to promise one scan and every
/// climb analyzed, which was neither the code nor the Terms.
@Suite("The free plan")
struct FreePlanTests {
    @Test("Three goes, and a go is anything that gives feedback")
    @MainActor
    func threeGoes() {
        #expect(Store.freeAnalyses == 3)
        let store = Store.shared
        // A scan and a climb cost the same thing: one of the three.
        #expect(store.freeAnalysesLeft <= Store.freeAnalyses)
        #expect(store.needsPro == (store.freeAnalysesLeft == 0))
    }
}
