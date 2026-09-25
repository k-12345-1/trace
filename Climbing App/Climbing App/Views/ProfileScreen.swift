import SwiftUI

/// Who you are, what you can change, and how to leave.
///
/// Built out of the same pieces as the rest of the app rather than out of
/// another app's settings screen, which is what it was: a hundred-and-eight
/// point avatar tile, a full width navy pill, bold sans labels, and round icon
/// wells, none of which appear anywhere else in Trace.
///
/// So it is a page like the others now: a serif name at the gutter, a strip of counts
/// exactly as a route shows its counts, and one card of rows split by
/// hairlines, the last two of which end something rather than go somewhere.
/// Everything that was on it is still on it.
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
                }
                .padding(.bottom, 156)
                .holdsThePageWidth()
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

    /// The name and when they joined, set the way every other page in the app
    /// sets its title: a serif line at the gutter with a grey one under it.
    ///
    /// No initials square. A monogram is a stand-in for a picture on a row in a
    /// list, which is what it does for a gym, and this is not a row: it is the
    /// top of the only page that is about you, where the name is enough.
    private var header: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        ], alignment: .center)
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
                row(icon: AnyView(StrokeIcon(shape: Ic.User(), size: 24, color: Theme.blue)),
                    label: "Personal info", detail: bodyDetail)
            }
            .buttonStyle(.plain)

            Hairline()

            NavigationLink { SubscriptionScreen() } label: {
                row(icon: AnyView(Image(systemName: "creditcard")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Manage subscription", detail: subscriptionDetail)
            }
            .buttonStyle(.plain)

            Hairline()

            NavigationLink { LegalScreen.privacy() } label: {
                row(icon: AnyView(Image(systemName: "checkmark.shield")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Privacy & AI", detail: "On-device analysis · Policy")
            }
            .buttonStyle(.plain)

            Hairline()

            Button { confirmingSignOut = true } label: {
                row(icon: AnyView(Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)),
                    label: "Sign out", detail: "End your session", leaving: true)
            }
            .buttonStyle(.plain)

            Hairline()

            Button { confirmingDelete = true } label: {
                row(icon: AnyView(Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)),
                    label: "Delete account", detail: "Permanently remove your data",
                    leaving: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

    /// A square well, a serif label, a line of detail, a chevron. The square is
    /// the shape everything else in the app puts a picture in; the round wells
    /// this used belonged to a different app.
    /// `leaving` marks the two that end something rather than go somewhere.
    /// This palette has no red, so they invert their well instead: a white mark
    /// on the dark blue rather than a dark mark on a pale one. They also have
    /// no chevron, because there is nowhere to arrive.
    private func row(icon: AnyView, label: String, detail: String,
                     leaving: Bool = false) -> some View {
        HStack(spacing: 16) {
            icon
                .frame(width: 52, height: 52)
                .background(leaving ? Theme.blue : Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Theme.serif(19, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !leaving {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(minHeight: 76)
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
                .holdsThePageWidth()
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
