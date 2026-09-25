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
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
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
    //
    // Tiles with the name underneath rather than cards with the name inside.
    // A square holds a logo, a photograph or a wall of colours equally well,
    // and putting the label outside it means the tile never has to reserve
    // space for text it might not need.

    private var gyms: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Your gyms")
                Spacer(minLength: 12)
                if !store.gyms.isEmpty {
                    NavigationLink { GymsScreen() } label: {
                        Text("View all")
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    NavigationLink { ExploreScreen() } label: {
                        GymTile(name: "Explore", sub: "Everything scanned") {
                            ZStack {
                                Theme.blueLight
                                Image(systemName: "map")
                                    .font(.system(size: 32, weight: .regular))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(store.gyms) { gym in
                        NavigationLink { RoutesScreen(gym: gym) } label: { tile(gym) }
                            .buttonStyle(.plain)
                    }

                    Button { namingGym = true } label: {
                        GymTile(name: "Add new", sub: "Name a gym") {
                            ZStack {
                                Theme.accentWash
                                Image(systemName: "plus")
                                    .font(.system(size: 30, weight: .light))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 26)
    }

    private func tile(_ gym: Gym) -> some View {
        let counts = store.routeCount(in: gym)
        let colours = store.routes(in: gym).prefix(9).map { Color(hexString: $0.colorHex) }
        return GymTile(
            name: gym.name,
            sub: "\(counts.total) route\(counts.total == 1 ? "" : "s")",
            sent: counts.sent > 0
        ) {
            ZStack {
                Theme.surface
                if colours.isEmpty {
                    Text(initials(of: gym.name))
                        .font(Theme.serif(34, .semibold))
                        .foregroundStyle(Theme.blue)
                } else {
                    // The wall itself, as the colours set on it. It is the only
                    // picture of a gym Trace actually has.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                             count: 3), spacing: 5) {
                        ForEach(Array(colours.enumerated()), id: \.offset) { _, colour in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(colour)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func initials(of name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "G" : String(letters).uppercased()
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
                Text("Nothing yet. Record a boulder or import a clip you already have, and Trace will analyze your movement pattern.")
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

// MARK: - Gym tile

/// A square, then the name, then one line under it. The check sits beside the
/// name rather than on the tile, so a photograph is never covered by a badge.
private struct GymTile<Face: View>: View {
    let name: String
    let sub: String
    var sent: Bool = false
    @ViewBuilder var face: Face

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            face
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(Theme.ui(15.5, .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if sent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.blueLight)
                    }
                }
                Text(sub)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
        }
        .frame(width: 128, alignment: .leading)
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
