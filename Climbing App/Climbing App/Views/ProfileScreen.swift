import SwiftUI

/// Who you are, and how to stop being them.
///
/// The rows below the identity block are the shape from the sketch. Only the
/// ones Trace can actually honour are live: a row that opened nothing would be
/// worse than a row that says it is not built yet.
struct ProfileScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var confirming = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identity
                    rows
                    storage
                    signOut
                }
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .alert("Sign out?", isPresented: $confirming) {
            Button("Sign out", role: .destructive) { store.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your climbs stay on this phone.")
        }
    }

    // MARK: Identity

    private var identity: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(store.account?.initials ?? "C")
                .font(Theme.ui(19, .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(store.account?.displayName ?? "Climber")
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.ink)
                if let account = store.account {
                    Text("Member since \(account.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.ui(13.5))
                        .foregroundStyle(Theme.ink3)
                    Text(account.isLocalOnly
                         ? "On this phone only. No email, no server."
                         : account.email)
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 16)
        .padding(.bottom, 26)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Profile")
                .padding(.horizontal, Theme.gutter)

            VStack(spacing: 4) {
                NavigationLink { PersonalInfoScreen() } label: {
                    row("Personal info", detail: bodyDetail, ready: true)
                }
                .buttonStyle(.plain)
                row("Billing", detail: "Nothing to pay for yet", ready: false)
                row("Privacy and AI", detail: "Everything stays on device", ready: false)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.top, 6)
    }

    private func row(_ title: String, detail: String, ready: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(ready ? Theme.ink : Theme.ink2)
                Text(detail)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer()
            if ready {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            } else {
                Text("Not built yet")
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .card()
        .contentShape(Rectangle())
    }

    /// The row says what is set, so the screen behind it is not the only way to
    /// find out whether Trace knows your height.
    private var bodyDetail: String {
        let b = store.body
        switch (b.heightCM, b.spanCM) {
        case (nil, nil):   return "Height and reach"
        case (_, nil):     return "Height \(b.describe(b.heightCM)) · no reach"
        case (nil, _):     return "Reach \(b.describe(b.spanCM)) · no height"
        default:           return "\(b.describe(b.heightCM)) · \(b.describe(b.spanCM))"
        }
    }

    // MARK: Where it lives

    private var storage: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Where your climbing lives")
            Text("On this phone. Trace measures everything on device and uploads nothing, with or without an account. Signing out leaves every climb, route and gym exactly where it is.")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .padding(.bottom, 24)
    }

    private var signOut: some View {
        FlatButton(title: store.account?.isLocalOnly == true ? "Switch account" : "Sign out") {
            confirming = true
        }
        .padding(.horizontal, Theme.gutter)
    }
}
