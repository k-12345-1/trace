import SwiftUI
import StoreKit

/// The one place Trace asks for money.
///
/// It appears when someone opens the scanner for the second time. The first scan
/// is free and complete, not a teaser: you get the holds, the gym, the route
/// saved, all of it. That is deliberate. Nobody can tell from a screenshot
/// whether colour segmentation works on their gym's lighting, so the honest way
/// to sell it is to let them find out on their own wall first.
///
/// Everything already scanned stays scanned whether or not they pay here.
/// Taking away work someone has already done is not a paywall, it is a hostage.
struct PaywallScreen: View {
    /// Called when the person is now Pro, so the screen they were trying to
    /// reach can open instead of making them find it again.
    var onUnlocked: () -> Void = {}

    @ObservedObject private var billing = Subscription.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavHeader(title: nil) { dismiss() }
                    mark
                    header
                    included
                    price
                    buttons
                    smallprint
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        // Full screen, not a card over the price. These are the documents the
        // purchase is made under.
        .fullScreenCover(isPresented: $showTerms) { LegalScreen.terms(insideApp: false) }
        .fullScreenCover(isPresented: $showPrivacy) { LegalScreen.privacy(insideApp: false) }
        .alert("That did not go through",
               isPresented: Binding(get: { billing.problem != nil },
                                    set: { if !$0 { billing.problem = nil } })) {
            Button("OK", role: .cancel) { billing.problem = nil }
        } message: {
            Text(billing.problem ?? "")
        }
        .task { await billing.load() }
    }

    private var mark: some View {
        MountainMark(color: Theme.blue)
            .frame(width: 46, height: 46)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep climbing")
                .font(Theme.title(32))
                .foregroundStyle(Theme.ink)
            Text("Your first route was free. Scanning more of the wall, and everything Trace works out from them, is part of Trace Pro.")
                .font(Theme.ui(15.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
        .padding(.bottom, 26)
    }

    private var included: some View {
        VStack(spacing: 10) {
            line("Unlimited route scans",
                 "Photograph a wall, tap one hold, and Trace picks out the rest by colour.")
            line("Recommended climbs",
                 "Routes off your own walls chosen for the thing you are working on.")
            line("Unlimited climbs analysed",
                 "Every clip measured on this phone, with the attempt-against-attempt history that makes the numbers mean anything.")
            line("Everything stays on the phone",
                 "Paying changes what Trace does, not where your footage goes. It still uploads nothing.")
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func line(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.blue))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.ui(15.5, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    // MARK: Choosing how to pay
    //
    // Two rows rather than a segmented control, because the thing being chosen
    // is a price and a price needs room to be read. Same features either way,
    // which is why neither row lists any.

    private var price: some View {
        VStack(spacing: 8) {
            ForEach(Subscription.Plan.allCases) { plan in
                planRow(plan)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 26)
    }

    private func planRow(_ plan: Subscription.Plan) -> some View {
        let chosen = billing.plan == plan
        return Button {
            billing.plan = plan
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(chosen ? Theme.accent : Theme.lineStrong, lineWidth: chosen ? 6 : 1.5)
                        .frame(width: 21, height: 21)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .font(Theme.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                    if plan == .yearly, let each = billing.yearlyPerMonth {
                        Text("\(each) a month, billed once a year")
                            .font(Theme.ui(12.5))
                            .foregroundStyle(Theme.ink3)
                    } else {
                        Text("Billed every month")
                            .font(Theme.ui(12.5))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(billing.price(plan))
                        .font(Theme.serif(20, .semibold))
                        .foregroundStyle(Theme.ink)
                    if plan == .yearly, let saving = billing.yearlySaving {
                        Text("Save \(saving)%")
                            .font(Theme.ui(11, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity)
            .background(chosen ? Theme.accentWash : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .stroke(chosen ? Theme.accent : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button {
                Task { if await billing.buy() { onUnlocked(); dismiss() } }
            } label: {
                ZStack {
                    if billing.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Subscribe")
                            .font(Theme.ui(16.5, .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Theme.accent)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(billing.isPurchasing)

            Button {
                Task { await billing.restore(); if billing.isPro { onUnlocked(); dismiss() } }
            } label: {
                Text("Restore a purchase")
                    .font(Theme.ui(14.5, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
    }

    /// The disclosures Apple's guidelines require next to the button: what is
    /// charged, how often, that it renews, and how to stop it.
    private var smallprint: some View {
        VStack(spacing: 12) {
            Text("Billed through your Apple ID at \(billing.priceText) each \(billing.periodText). It renews on its own until you turn renewal off, which you can do at any time in Settings under your name, then Subscriptions. Turning it off at least a day before the next charge stops that charge. Cancelling never touches anything already on your phone.")
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Button("Terms") { showTerms = true }
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
                Button("Privacy Policy") { showPrivacy = true }
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 20)
    }
}
