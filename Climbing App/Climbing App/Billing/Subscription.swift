import Foundation
import StoreKit

/// Trace Pro: one subscription, billed monthly or yearly, bought through the
/// App Store.
///
/// Apple takes the payment. Apple Pay, the card on the Apple ID, or whatever
/// else the person has set up is the App Store's business, not Trace's, which is
/// why there is no card form anywhere in this app and no payment detail ever
/// reaches it. Apple requires that for a subscription unlocking features inside
/// the app, and it is also the arrangement that keeps Trace's promise that
/// nothing about you leaves the phone: a payment Trace never sees is a payment
/// Trace cannot leak.
///
/// Entitlement is read from StoreKit itself rather than from a flag Trace writes
/// down. A local flag would be one canceled subscription away from being a lie,
/// and it would be trivially editable on a jailbroken device. `Transaction`
/// is the truth, it is verified by Apple, and it survives a reinstall.
@MainActor
final class Subscription: ObservableObject {

    static let shared = Subscription()

    /// Two products, one subscription. Same features either way: the choice is
    /// how often it bills, not what you get, because a cheaper tier that takes
    /// something away would make the paywall a menu rather than a decision.
    enum Plan: String, CaseIterable, Identifiable {
        case yearly  = "co.traceclimb.pro.yearly"
        case monthly = "co.traceclimb.pro.monthly"

        var id: String { rawValue }
        var title: String { self == .yearly ? "Yearly" : "Monthly" }
    }

    static var productIDs: [String] { Plan.allCases.map(\.rawValue) }

    /// What the store says right now.
    @Published private(set) var isPro = false
    /// The products, once the App Store has handed them over. Empty while
    /// loading, and empty forever if the device is offline, which the paywall
    /// has to survive.
    @Published private(set) var products: [Plan: Product] = [:]
    /// Which one the paywall has selected. Yearly leads because it is the
    /// cheaper way to pay for the same thing.
    @Published var plan: Plan = .yearly
    @Published private(set) var isPurchasing = false

    /// Whether the App Store has answered yet.
    ///
    /// The paywall used to have no idea. It drew the fallback prices whether
    /// the products had arrived or not, so an offline phone showed a finished
    /// screen with a live Subscribe button on it, and the only way to find out
    /// the store had never answered was to press that button and be told so.
    /// A button that cannot succeed should say so before it is pressed.
    enum StoreState { case loading, ready, unavailable }
    @Published private(set) var storeState: StoreState = .loading
    var canBuy: Bool { products[plan] != nil }
    /// Set when a purchase fails for a reason worth showing. Cancellation is not
    /// one: someone who taps Cancel does not need to be told they canceled.
    @Published var problem: String?

    private var updates: Task<Void, Never>?

    private init() {
        // Started before anything else. A subscription can change outside the
        // app (renewal, cancellation, a refund, a family member's purchase) and
        // this is the only way Trace hears about it.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = result { await t.finish() }
                await self.refresh()
            }
        }
        Task { await load(); await refresh() }
    }

    deinit { updates?.cancel() }

    // MARK: Reading the store

    /// Ask the App Store for the two products.
    ///
    /// Called on every appearance of the paywall rather than once at launch.
    /// Once was the bug: `Subscription` is a singleton built the first time
    /// anything touches it, which on a cold launch is before the phone has
    /// finished joining a network, and nothing ever asked again. The store
    /// stayed permanently empty for the life of the process and every purchase
    /// failed with a message about the connection on a phone that was online.
    ///
    /// A failure is distinguished from an answer. `Product.products(for:)`
    /// returns only the ids the store recognises, so an empty array is the App
    /// Store saying these products do not exist, which is a different problem
    /// from not reaching it at all, and a person can act on neither if both
    /// read the same.
    @discardableResult
    func load() async -> Bool {
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = Dictionary(uniqueKeysWithValues: fetched.compactMap { p in
                Plan(rawValue: p.id).map { ($0, p) }
            })
            storeState = products.isEmpty ? .unavailable : .ready
        } catch {
            products = [:]
            storeState = .unavailable
        }
        return storeState == .ready
    }

    /// The live entitlement, straight from StoreKit.
    func refresh() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result,
                  Plan(rawValue: t.productID) != nil,
                  t.revocationDate == nil else { continue }
            // An expired subscription still appears here, so the date is checked
            // rather than assumed.
            if let expiry = t.expirationDate, expiry < .now { continue }
            isPro = true
            return
        }
        isPro = false
    }

    // MARK: Buying

    /// Returns true when the purchase went through, so the caller can carry on
    /// into whatever the person was trying to do.
    @discardableResult
    func buy() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        // One more try before giving up. The products may simply not have
        // arrived yet: the paywall can be opened within a second of launch, and
        // the first request can lose a race with the network coming up.
        if products[plan] == nil { await load() }
        guard let product = products[plan] else {
            problem = "Trace could not reach the App Store to load its prices. Check your connection and try again."
            return false
        }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else {
                    problem = "That purchase could not be verified by Apple."
                    return false
                }
                await t.finish()
                await refresh()
                return isPro
            case .pending:
                // Ask to Buy, or a payment the bank still has to approve.
                problem = "That purchase is waiting on approval. Trace will unlock as soon as it goes through."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// For someone who already paid on another device, or who reinstalled.
    /// Apple requires this control to exist wherever a purchase can be made.
    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
            if !isPro { problem = "No subscription was found on this Apple ID." }
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: Display

    /// The price as the App Store formats it, in the person's own currency.
    /// The hard-coded fallbacks are only ever seen offline.
    func price(_ plan: Plan) -> String {
        products[plan]?.displayPrice ?? (plan == .yearly ? "$30.00" : "$4.99")
    }

    func period(_ plan: Plan) -> String {
        plan == .yearly ? "year" : "month"
    }

    var priceText: String { price(plan) }
    var periodText: String { period(plan) }

    /// What a year costs when paid monthly, so the yearly saving is a number
    /// rather than a claim. Nil when the two prices are not comparable.
    var yearlySaving: Int? {
        guard let m = products[.monthly]?.price, let y = products[.yearly]?.price else {
            return 50   // 4.99 × 12 = 59.88 against 30.00, offline fallback
        }
        let full = m * 12
        guard full > y, full > 0 else { return nil }
        return Int((((full - y) / full) * 100 as Decimal as NSDecimalNumber).doubleValue.rounded())
    }

    /// The yearly price said per month, which is how people compare the two.
    var yearlyPerMonth: String? {
        guard let y = products[.yearly] else { return "$2.50" }
        return y.priceFormatStyle.format(y.price / 12)
    }
}
