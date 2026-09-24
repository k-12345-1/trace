import Foundation
import StoreKit

/// Trace Pro: one monthly subscription, bought through the App Store.
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
/// down. A local flag would be one cancelled subscription away from being a lie,
/// and it would be trivially editable on a jailbroken device. `Transaction`
/// is the truth, it is verified by Apple, and it survives a reinstall.
@MainActor
final class Subscription: ObservableObject {

    static let shared = Subscription()

    /// The single product. One plan, one price, no tiers to compare.
    static let monthlyID = "co.traceclimb.pro.monthly"

    /// What the store says right now.
    @Published private(set) var isPro = false
    /// The product, once the App Store has handed it over. Nil while loading, and
    /// nil forever if the device is offline, which the paywall has to survive.
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    /// Set when a purchase fails for a reason worth showing. Cancellation is not
    /// one: someone who taps Cancel does not need to be told they cancelled.
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

    func load() async {
        do {
            product = try await Product.products(for: [Self.monthlyID]).first
        } catch {
            // Offline. The paywall falls back to naming the price in text, which
            // is better than an empty screen, and Buy will still work once the
            // App Store answers.
            product = nil
        }
    }

    /// The live entitlement, straight from StoreKit.
    func refresh() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result,
                  t.productID == Self.monthlyID,
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
        guard let product else {
            problem = "The App Store is not reachable. Check your connection and try again."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }

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
    /// The hard-coded fallback is only ever seen offline, and it is marked as
    /// the US price rather than pretending to be local.
    var priceText: String {
        product?.displayPrice ?? "$9.99"
    }

    var periodText: String {
        guard let unit = product?.subscription?.subscriptionPeriod.unit else { return "month" }
        switch unit {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        @unknown default: return "month"
        }
    }
}
