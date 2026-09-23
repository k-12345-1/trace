import SwiftUI

/// Home: what you are working on, where you climb, and everything you have climbed.
struct HomeScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var namingGym = false
    @State private var newGymName = ""

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                    Hairline()
                    focusBanner
                    gyms
                    Hairline()
                    library
                }
                // Clear of the tab bar.
                .padding(.bottom, 96)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("New gym", isPresented: $namingGym) {
            TextField("Name", text: $newGymName)
            Button("Add") {
                let name = newGymName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { _ = store.addGym(named: name) }
                newGymName = ""
            }
            Button("Cancel", role: .cancel) { newGymName = "" }
        } message: {
            Text("Whatever you call it. Trace has no directory of gyms and does not need one.")
        }
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRACE")
                    .font(Theme.ui(16, .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.blue)
                Spacer()
                MicroLabel(text: "\(store.climbs.count) climb\(store.climbs.count == 1 ? "" : "s")")
            }
            Text("The partner who watches you climb.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    // MARK: The session opening
    //
    // A partner picks up where you left off rather than greeting you blank.

    @ViewBuilder
    private var focusBanner: some View {
        if let focus = store.focus {
            NavigationLink { ProgressScreen() } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        MicroLabel(
                            text: focus.isResolved ? "Cleared" : "Working on · day \(focus.daysActive)",
                            color: focus.isResolved ? Theme.ok : Theme.blueLight
                        )
                        Spacer()
                        Text(focus.readout)
                            .font(Theme.mono(12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(focus.isResolved ? Theme.ok : Theme.blue)
                    }
                    Text(focus.kind.title)
                        .font(Theme.heading(17))
                        .foregroundStyle(Theme.ink)
                    Text(FocusEngine.greeting(for: focus))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(focus.isResolved ? Theme.surface : Theme.blueWash)
                .overlay(Rectangle().stroke(
                    focus.isResolved ? Theme.line : Theme.lineStrong, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Your gyms

    private var gyms: some View {
        VStack(alignment: .leading, spacing: 12) {
            MicroLabel(text: "Your gyms")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink { ExploreScreen() } label: {
                        GymCard(title: "Explore", subtitle: "Everything scanned",
                                symbol: "book", tint: Theme.blue)
                    }
                    .buttonStyle(.plain)

                    ForEach(store.gyms) { gym in
                        NavigationLink { RoutesScreen(gym: gym) } label: { card(gym) }
                            .buttonStyle(.plain)
                    }

                    Button { namingGym = true } label: {
                        GymCard(title: "Add new", subtitle: "Name a gym",
                                symbol: "plus", tint: Theme.accent, dashed: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private func card(_ gym: Gym) -> some View {
        let counts = store.routeCount(in: gym)
        return VStack(alignment: .leading, spacing: 0) {
            // The colours on that wall, at a glance.
            HStack(spacing: 3) {
                ForEach(Array(store.routes(in: gym).prefix(5).enumerated()), id: \.offset) { _, route in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hexString: route.colorHex))
                        .frame(width: 7, height: 18)
                }
                if counts.total == 0 {
                    Text("NOTHING SCANNED")
                        .font(Theme.mono(8, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 8)
            Text(gym.name)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(counts.total) route\(counts.total == 1 ? "" : "s") · \(counts.sent) sent")
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.ink3)
        }
        .frame(width: 134, height: 74, alignment: .topLeading)
        .padding(12)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: Theme.r).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.r))
    }

    // MARK: Your library

    private var library: some View {
        let entries = store.library()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                MicroLabel(text: "Your library")
                Spacer(minLength: 12)
                if store.climbs.contains(where: { $0.metrics.isTrustworthy }) {
                    NavigationLink { ProgressScreen() } label: {
                        Text("OVER TIME →")
                            .font(Theme.mono(10, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if entries.isEmpty {
                Text("Nothing yet. Record a boulder or import a clip you already have, and Trace will tell you where the energy went.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(entries) { entry in
                        NavigationLink { ClimbCardScreen(entry: entry) } label: {
                            LibraryCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Gym card

private struct GymCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var dashed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            Text(title)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.ink3)
        }
        .frame(width: 134, height: 74, alignment: .topLeading)
        .padding(12)
        .background(dashed ? Color.clear : Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.r)
                .stroke(dashed ? tint.opacity(0.55) : Theme.line,
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 4] : []))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.r))
    }
}

// MARK: - Library card

/// One route: what you called it, how many times you have been on it, and how
/// many of those went to the top.
struct LibraryCard: View {
    let entry: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClimbThumbnail(climb: entry.latest)
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 11)

            HStack(spacing: 6) {
                if let top = entry.topFinding {
                    SeverityChip(severity: top.severity)
                } else {
                    MicroLabel(text: "No findings")
                }
                Spacer(minLength: 0)
                if entry.sendCount > 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer(minLength: 10)

            Text(entry.name)
                .font(Theme.heading(15))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                count(entry.attemptCount, "attempt")
                count(entry.sendCount, "send")
            }
            Text(entry.lastClimbed.formatted(date: .abbreviated, time: .omitted))
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.ink3)
                .padding(.top, 4)
        }
        .frame(height: 232, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(13)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: Theme.r).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.r))
    }

    private func count(_ n: Int, _ noun: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(n)")
                .font(Theme.mono(13, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(n == 1 ? noun : noun + "s")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
        }
    }
}
