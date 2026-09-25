import SwiftUI

/// Who you are, what you can change, and how to leave.
///
/// The same five rows the Lineage Health settings screen has, in the same
/// shape: a large avatar tile beside a name set over two lines, a pair of small
/// stats, a full-width member pill, then one card of rows made of a round icon
/// well, a bold label, a line of detail and a chevron.
///
/// That app marks its two leaving rows in red. This palette has no red, so they
/// invert their wells instead: a white mark on the dark blue rather than a dark
/// mark on a pale one.
struct ProfileScreen: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var billing = Subscription.shared
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    memberPill
                    SectionTitle("Profile")
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                    rows
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .alert("Sign out?", isPresented: $confirmingSignOut) {
            Button("Sign out", role: .destructive) { store.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your climbs stay on this phone.")
        }
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Delete everything", role: .destructive) { store.deleteEverything() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every climb, clip, route and gym on this phone is removed, along with your height, reach and weight. This cannot be undone.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 26) {
            Text(store.account?.initials ?? "C")
                .font(Theme.serif(38, .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 108, height: 108)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(nameLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Theme.serif(30, .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                HStack(spacing: 22) {
                    stat("\(store.climbs.count)", "Climbs")
                    stat("\(store.gyms.count)", "Gyms")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
    }

    /// The name over two lines, the way the reference sets a first and last.
    /// A single word stays on one line rather than being broken to fill two.
    private var nameLines: [String] {
        let name = store.account?.displayName ?? "Climber"
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.isEmpty ? ["Climber"] : parts
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Theme.ui(14, .medium)).monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label.uppercased())
                .font(Theme.ui(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.ink3)
        }
    }

    private var memberPill: some View {
        Text(memberText)
            .font(Theme.ui(13, .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.blue)
            .clipShape(Capsule())
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 20)
    }

    private var memberText: String {
        guard let created = store.account?.createdAt else { return "Member" }
        return "Member since \(created.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 4) {
            NavigationLink { PersonalInfoScreen() } label: {
                row(icon: AnyView(StrokeIcon(shape: Ic.User(), size: 22, color: Theme.blue)),
                    label: "Personal info", detail: bodyDetail)
            }
            .buttonStyle(.plain)

            NavigationLink { SubscriptionScreen() } label: {
                row(icon: AnyView(Image(systemName: "creditcard")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Manage subscription", detail: subscriptionDetail)
            }
            .buttonStyle(.plain)

            NavigationLink { LegalScreen.privacy() } label: {
                row(icon: AnyView(Image(systemName: "checkmark.shield")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Privacy & AI", detail: "On-device analysis · Policy")
            }
            .buttonStyle(.plain)

            Button { confirmingSignOut = true } label: {
                row(icon: AnyView(Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)),
                    label: "Sign out", detail: "End your session", leaving: true)
            }
            .buttonStyle(.plain)

            Button { confirmingDelete = true } label: {
                row(icon: AnyView(Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)),
                    label: "Delete account", detail: "Permanently remove your data",
                    leaving: true)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
    }

    private func row(icon: AnyView, label: String, detail: String,
                     leaving: Bool = false) -> some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 50, height: 50)
                .background(leaving ? Theme.blue : Theme.accentWash)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Theme.ui(18, .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .frame(minHeight: 68)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }

    private var subscriptionDetail: String {
        Subscription.shared.isPro ? "Trace Pro · active" : "Free · 1 route scan"
    }

    private var bodyDetail: String {
        let b = store.body
        var parts: [String] = []
        if b.heightCM != nil { parts.append(b.describe(b.heightCM)) }
        if b.spanCM != nil { parts.append(b.describe(b.spanCM)) }
        if b.massKG != nil { parts.append(b.describeMass(b.massKG)) }
        return parts.isEmpty ? "Height · reach · weight" : parts.joined(separator: " · ")
    }
}

// MARK: - Subscription

/// What you are on, what it costs, and how to stop it.
///
/// Trace cannot cancel a subscription itself. Apple owns that switch, which is
/// why this screen sends you to Settings rather than pretending to a control it
/// does not have.
struct SubscriptionScreen: View {
    @ObservedObject private var billing = Subscription.shared
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavHeader(title: nil) { dismiss() }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subscription")
                            .font(Theme.title(30))
                            .foregroundStyle(Theme.ink)
                        Text(billing.isPro
                             ? "Trace Pro is active on this Apple ID."
                             : "You are on the free plan.")
                            .font(Theme.ui(15))
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 22)

                    MetricStrip(items: [
                        .init(value: billing.isPro ? "Pro" : "Free", label: "Plan"),
                        .init(value: billing.isPro ? billing.priceText : "—", label: "Price"),
                        .init(value: "\(store.scansUsed)", label: "Scans used")
                    ])
                    .padding(18)
                    .card()
                    .padding(.horizontal, Theme.gutter)

                    VStack(spacing: 12) {
                        if !billing.isPro {
                            card("What the free plan includes",
                                 "One route scan, and every climb you record or import analyzed in full. Nothing you have already done is ever taken away.")
                            Button { showPaywall = true } label: {
                                Text("See Trace Pro")
                                    .font(Theme.ui(16, .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Theme.button)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            card("Cancelling",
                                 "Open Settings, tap your name, then Subscriptions, and turn off renewal for Trace. Do it at least a day before the next charge to stop that charge. Everything on this phone stays where it is.")
                        }
                        card("Where the payment goes",
                             "Through the App Store, billed to your Apple ID. Trace never sees your card or your billing details, and never receives a payment record with your name on it.")
                        card("Refunds",
                             "Handled by Apple under their own policy, at reportaproblem.apple.com. Trace cannot issue one.")

                        Button {
                            Task { await billing.restore() }
                        } label: {
                            Text("Restore a purchase")
                                .font(Theme.ui(14.5, .semibold))
                                .foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        NavigationLink { LegalScreen.terms() } label: {
                            Text("Terms of Use")
                                .font(Theme.ui(14.5, .semibold))
                                .foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 22)
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showPaywall) {
            NavigationStack { PaywallScreen() }
        }
    }

    private func card(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(heading)
            Text(text)
                .font(Theme.ui(14.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .card()
    }
}
