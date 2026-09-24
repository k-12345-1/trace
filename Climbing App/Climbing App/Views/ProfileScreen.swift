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
    @State private var panel: Panel?
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false

    private enum Panel: String, Identifiable {
        case subscription, privacy
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .sheet(item: $panel) { which in
            switch which {
            case .subscription: InfoSheet.subscription
            case .privacy:      InfoSheet.privacy
            }
        }
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
            Text("Every climb, clip, route and gym on this phone is removed, along with your height and reach. This cannot be undone.")
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
                    stat("\(store.library().count)", "Routes")
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

            Button { panel = .subscription } label: {
                row(icon: AnyView(Image(systemName: "creditcard")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Manage subscription", detail: "Plan · payment")
            }
            .buttonStyle(.plain)

            Button { panel = .privacy } label: {
                row(icon: AnyView(Image(systemName: "checkmark.shield")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Privacy & AI", detail: "On-device analysis · Terms")
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

    private var bodyDetail: String {
        let b = store.body
        switch (b.heightCM, b.spanCM) {
        case (nil, nil):   return "Height · reach"
        case (_, nil):     return "Height \(b.describe(b.heightCM)) · no reach"
        case (nil, _):     return "Reach \(b.describe(b.spanCM)) · no height"
        default:           return "\(b.describe(b.heightCM)) · \(b.describe(b.spanCM))"
        }
    }
}

// MARK: - Panels

/// A row that opened nothing would be worse than no row. Each of these says the
/// thing that is actually true today rather than describing a feature that is
/// not built.
private struct InfoSheet: View {
    let title: String
    let paragraphs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.accentText)
                }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(Theme.ui(15))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(Theme.gutter)
        }
        .presentationDetents([.height(380)])
        .preferredColorScheme(.light)
    }

    static var subscription: InfoSheet {
        InfoSheet(title: "Subscription", paragraphs: [
            "Trace is free while it is being built, and there is nothing to pay for yet. No card is on file and no plan is running.",
            "When there is something to charge for, it will appear here with the price before anything is taken."
        ])
    }

    static var privacy: InfoSheet {
        InfoSheet(title: "Privacy & AI", paragraphs: [
            "Everything stays on this phone. Trace measures every climb on device and uploads nothing, so your clips never leave the handset. That is what makes filming in a gym full of other people unproblematic.",
            "The only model involved is Apple's on-device pose detector, which finds your joints in each frame. Nothing is sent to a language model, there is no analytics and there is no crash reporting.",
            "Signing out leaves every climb, route and gym exactly where it is. Deleting your account removes all of it."
        ])
    }
}
