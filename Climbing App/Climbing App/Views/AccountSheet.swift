import SwiftUI

/// Who you are, and how to stop being them.
struct AccountSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    MicroLabel(text: "Account")
                    Spacer()
                    Button("DONE") { dismiss() }
                        .font(Theme.mono(11, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(Theme.accentText)
                }

                if let account = store.account {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account.displayName)
                            .font(Theme.heading(21))
                            .foregroundStyle(Theme.ink)
                        Text(account.isLocalOnly
                             ? "On this phone only. No email, no server, nothing to sign out of anywhere else."
                             : account.email)
                            .font(Theme.body(13.5))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Hairline()

                VStack(alignment: .leading, spacing: 7) {
                    MicroLabel(text: "Where your climbing lives")
                    Text("On this phone. Trace measures everything on device and uploads nothing, with or without an account. Signing out leaves every climb, route and gym exactly where it is.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    confirming = true
                } label: {
                    Text((store.account?.isLocalOnly == true ? "Switch account" : "Sign out").uppercased())
                        .font(Theme.mono(11, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: Theme.r)
                            .stroke(Theme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
        }
        .preferredColorScheme(.light)
        .presentationDetents([.medium])
        .alert("Sign out?", isPresented: $confirming) {
            Button("Sign out", role: .destructive) { store.signOut(); dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your climbs stay on this phone.")
        }
    }
}
