import SwiftUI

/// Who you are, what you can change, and how to leave.
///
/// Built out of the same pieces as the rest of the app rather than out of
/// another app's settings screen, which is what it was: a hundred-and-eight
/// point avatar tile, a full width navy pill, bold sans labels, and round icon
/// wells, none of which appear anywhere else in Trace.
///
/// So it is a page like the others now. A serif title, a strip of counts
/// exactly as a route shows its counts, one card of rows split by hairlines,
/// and the two ways out set as underlined text at the foot of the page, the
/// way deleting a route is set on the route's own screen. Everything that was
/// on it is still on it.
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
                    counts
                    SectionTitle("Profile")
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 30)
                        .padding(.bottom, 12)
                    rows
                    leaving
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

    /// A square of their initials, the name, and when they joined. The square
    /// is the size a gym's square is, because it is the same idea: a small
    /// picture of who or what a row is about.
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(store.account?.initials ?? "C")
                .font(Theme.serif(24, .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 62, height: 62)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rTile * 0.62,
                                            style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(nameLines.joined(separator: " "))
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(memberText)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 16)
    }

    /// The same strip a route uses for its own counts, rather than two stats in
    /// a shape that appears nowhere else.
    private var counts: some View {
        MetricStrip(items: [
            .init(value: "\(store.climbs.count)",
                  label: store.climbs.count == 1 ? "Climb" : "Climbs"),
            .init(value: "\(store.gyms.count)",
                  label: store.gyms.count == 1 ? "Gym" : "Gyms"),
            .init(value: "\(store.routes.count)",
                  label: store.routes.count == 1 ? "Route" : "Routes")
        ])
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 26)
    }

    /// The name over two lines, the way the reference sets a first and last.
    /// A single word stays on one line rather than being broken to fill two.
    private var nameLines: [String] {
        let name = store.account?.displayName ?? "Climber"
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.isEmpty ? ["Climber"] : parts
    }

    private var memberText: String {
        guard let created = store.account?.createdAt else { return "Member" }
        return "Member since \(created.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            NavigationLink { PersonalInfoScreen() } label: {
                row(icon: AnyView(StrokeIcon(shape: Ic.User(), size: 21, color: Theme.blue)),
                    label: "Personal info", detail: bodyDetail)
            }
            .buttonStyle(.plain)

            Hairline()

            NavigationLink { SubscriptionScreen() } label: {
                row(icon: AnyView(Image(systemName: "creditcard")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Manage subscription", detail: subscriptionDetail)
            }
            .buttonStyle(.plain)

            Hairline()

            // The one switch in the app, because it is the one thing Trace
            // does over the network that is not your account or your
            // subscription. It says what it costs rather than being a word
            // with a toggle beside it.
            logoSwitch

            Hairline()

            NavigationLink { LegalScreen.privacy() } label: {
                row(icon: AnyView(Image(systemName: "checkmark.shield")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Privacy & AI", detail: "On-device analysis · Policy")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

    /// The two ways out, set the way deleting a route is set on the route's own
    /// screen: underlined text at the foot of the page, not a row with an icon
    /// that looks like somewhere to go.
    private var leaving: some View {
        VStack(spacing: 22) {
            way("Sign out", "End your session") { confirmingSignOut = true }
            way("Delete account", "Permanently remove your data") { confirmingDelete = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
    }

    private func way(_ label: String, _ detail: String,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .underline()
                Text(detail)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var logoSwitch: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.blue)
                .frame(width: 44, height: 44)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Gym logos")
                    .font(Theme.serif(17.5, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Fetched once from each gym's own site and kept here. Nothing about you goes with the request; off means initials.")
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { store.fetchesGymLogos },
                                     set: { store.setFetchesGymLogos($0) }))
                .labelsHidden()
                .tint(Theme.button)
        }
        .padding(.vertical, 12)
    }

    /// A square well, a serif label, a line of detail, a chevron. The square is
    /// the shape everything else in the app puts a picture in; the round wells
    /// this used belonged to a different app.
    private func row(icon: AnyView, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 44, height: 44)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Theme.serif(17.5, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink3)
        }
        .frame(minHeight: 62)
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
