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
                    focusBanner
                    SuggestedRoutes()
                    gyms
                    library
                }
                // Clear of the tab bar.
                .padding(.bottom, 120)
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
            HStack(alignment: .center, spacing: 10) {
                MountainMark(color: .white, inset: 0.16)
                    .frame(width: 30, height: 30)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Trace")
                    .font(Theme.serif(24, .semibold))
                    .foregroundStyle(Theme.blue)
                Spacer()
                Text("\(store.climbs.count) climb\(store.climbs.count == 1 ? "" : "s")")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 18)
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
                        .font(Theme.serif(21, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(FocusEngine.greeting(for: focus))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .card(fill: focus.isResolved ? Theme.surface : Theme.blueWash)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Your gyms

    private var gyms: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Your gyms")
                .padding(.horizontal, Theme.gutter)

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
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 26)
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
                    Text("Nothing scanned")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 8)
            Text(gym.name)
                .font(Theme.serif(16.5, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(counts.total) route\(counts.total == 1 ? "" : "s") · \(counts.sent) sent")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
        }
        .frame(width: 152, height: 86, alignment: .topLeading)
        .padding(14)
        .card()
    }

    // MARK: Your library

    // MARK: Your library
    //
    // A preview rather than the whole thing. The library has its own screen, and
    // Home is about what you are doing today.

    private var library: some View {
        let entries = store.library()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Your library")
                Spacer(minLength: 12)
                if !entries.isEmpty {
                    NavigationLink { LibraryScreen() } label: {
                        Text("See all \(entries.count)")
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)

            if entries.isEmpty {
                Text("Nothing yet. Record a boulder or import a clip you already have, and Trace will tell you where the energy went.")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                    GridItem(.flexible(), spacing: 13)], spacing: 16) {
                    ForEach(entries.prefix(4)) { entry in
                        NavigationLink { ClimbCardScreen(entry: entry) } label: {
                            LibraryCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Section title

/// Sentence case and the interface font. The old uppercase mono headings turned
/// every list into a control panel.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.serif(21, .semibold))
            .foregroundStyle(Theme.ink)
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
                .font(Theme.serif(16.5, .semibold))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(Theme.ui(13))
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
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if entry.sendCount > 0 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(Theme.accent))
                            .padding(8)
                    }
                }

            Text(entry.name)
                .font(Theme.serif(17.5, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 5) {
                if let top = entry.topFinding {
                    Circle()
                        .fill(Theme.ember[min(top.severity.rawValue, Theme.ember.count - 1)])
                        .frame(width: 8, height: 8)
                    Text(top.severity.label)
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink2)
                } else {
                    Text("No findings")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.top, 4)

            Text(meta)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The one line under the name. It has half a screen to live in, so the
    /// send count only appears once there is one to report.
    private var meta: String {
        var parts = ["\(entry.attemptCount) attempt\(entry.attemptCount == 1 ? "" : "s")"]
        if entry.sendCount > 0 { parts.append("\(entry.sendCount) sent") }
        parts.append(entry.lastClimbed.formatted(.dateTime.month(.abbreviated).day()))
        return parts.joined(separator: " · ")
    }

}
