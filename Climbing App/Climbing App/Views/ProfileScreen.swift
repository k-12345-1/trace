import SwiftUI

/// Who you are, and how to stop being them.
///
/// Laid out like the Lineage Health settings screen: a large square avatar
/// beside the name set over two lines, a pair of small stats under it, a
/// full-width member pill, then one card holding every row. Each row is a round
/// icon well, a bold label, a line of detail and a chevron. The reference marks
/// its destructive row in red; this palette has none, so that row inverts its
/// well instead.
struct ProfileScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var confirming = false
    @State private var showPrivacy = false

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
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showPrivacy) { PrivacySheet() }
        .alert("Sign out?", isPresented: $confirming) {
            Button("Sign out", role: .destructive) { store.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your climbs stay on this phone.")
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

            Button { showPrivacy = true } label: {
                row(icon: AnyView(Image(systemName: "lock")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(Theme.blue)),
                    label: "Privacy", detail: "Where your climbing lives")
            }
            .buttonStyle(.plain)

            Button { confirming = true } label: {
                row(icon: AnyView(Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)),
                    label: store.account?.isLocalOnly == true ? "Switch account" : "Sign out",
                    detail: "End your session",
                    danger: true)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
    }

    private func row(icon: AnyView, label: String, detail: String,
                     danger: Bool = false) -> some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 50, height: 50)
                // No red left in the palette, so the row that ends your session
                // is told apart by inverting its well rather than by hue.
                .background(danger ? Theme.blue : Theme.accentWash)
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

// MARK: - Privacy

/// A row that opens nothing would be worse than no row, so this one says the
/// only thing there is to say about where the data goes: nowhere.
private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle("Privacy")
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.accentText)
                }
                Text("On this phone. Trace measures everything on device and uploads nothing, with or without an account. Signing out leaves every climb, route and gym exactly where it is.")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("There is no analytics, no crash reporting and no third party in the pipeline. Your clips never leave the device, which is what makes filming in a gym full of other people unproblematic.")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(Theme.gutter)
        }
        .presentationDetents([.height(360)])
        .preferredColorScheme(.light)
    }
}
