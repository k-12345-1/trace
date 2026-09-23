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
                    Hairline()
                    rows
                    storage
                    signOut
                }
                .padding(.bottom, 96)
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
                .font(Theme.mono(15, weight: .medium))
                .foregroundStyle(Theme.blue)
                .frame(width: 52, height: 52)
                .background(Theme.blueWash)
                .overlay(RoundedRectangle(cornerRadius: Theme.r)
                    .stroke(Theme.lineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.r))

            VStack(alignment: .leading, spacing: 6) {
                Text(store.account?.displayName.uppercased() ?? "CLIMBER")
                    .font(Theme.ui(21, .bold))
                    .foregroundStyle(Theme.ink)
                if let account = store.account {
                    MicroLabel(
                        text: "Member since \(account.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    Text(account.isLocalOnly
                         ? "On this phone only. No email, no server."
                         : account.email)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Profile")
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                NavigationLink { PersonalInfoScreen() } label: {
                    row("Personal info", detail: bodyDetail, ready: true)
                }
                .buttonStyle(.plain)
                row("Billing", detail: "Nothing to pay for yet", ready: false)
                row("Privacy and AI", detail: "Everything stays on device", ready: false)
            }
            .background(Theme.line)
        }
        .padding(.top, 20)
    }

    private func row(_ title: String, detail: String, ready: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.heading(15.5))
                    .foregroundStyle(ready ? Theme.ink : Theme.ink2)
                Text(detail)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer()
            if ready {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            } else {
                MicroLabel(text: "Not built yet")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 15)
        .background(Theme.ground)
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
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: "Where your climbing lives")
            Text("On this phone. Trace measures everything on device and uploads nothing, with or without an account. Signing out leaves every climb, route and gym exactly where it is.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 24)
    }

    private var signOut: some View {
        FlatButton(title: store.account?.isLocalOnly == true ? "Switch account" : "Sign out") {
            confirming = true
        }
        .padding(.horizontal, 20)
    }
}
