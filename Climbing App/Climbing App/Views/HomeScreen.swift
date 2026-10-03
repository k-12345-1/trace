import SwiftUI

/// Home: what you are working on, where you climb, and everything you have climbed.
struct HomeScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var namingGym = false
    @State private var newGymName = ""

    var body: some View {
        ZStack {
            PaperGround()
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
                .holdsThePageWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationDestination(item: savedRoute) { RouteDetailScreen(route: $0) }
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
                // No tile and no border: the artwork is already a print on
                // paper, and boxing it makes it look like a sticker of itself.
                //
                // Bigger than a conventional masthead glyph would be, because
                // this is a stippled print rather than an icon. Below about
                // forty points the texture stops resolving and the figure turns
                // into a smudge, so the mark is given the room it needs.
                MountainMark(inset: 0)
                    .frame(width: 52, height: 52)
                // The drawn word, not the system serif. Set in type it was a
                // second letterform sitting six points from the first.
                //
                // Smaller than the figure, as it is in the artwork. The word is
                // a heavy slab and the figure is a thin stipple, so matching
                // their heights would let the word swallow the mark.
                TraceWordmark(height: 25)
                Spacer()
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    // MARK: The session opening
    //
    // A partner picks up where you left off rather than greeting you blank.

    /// A route just saved opens itself, from wherever on this stack the
    /// scan was started.
    private var savedRoute: Binding<Route?> {
        Binding(get: { store.justSaved }, set: { store.justSaved = $0 })
    }

    @ViewBuilder
    private var focusBanner: some View {
        // Nothing to work on until something has been climbed on camera.
        if let focus = store.focus, !store.climbs.isEmpty {
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
    // A square holds a logo, a photograph or a wall of colors equally well,
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
                        GymTile(name: "Explore") {
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
                        GymTile(name: "Add gym") {
                            // Paper with a drawn edge, not a filled block. A
                            // wash of ink over cream composites to a cold
                            // lavender, and an empty slot should look like an
                            // empty slot anyway.
                            ZStack {
                                Theme.surface
                                // The tile's own radius, not a smaller one.
                                // Drawn at eighteen inside a twenty-two point
                                // clip, the corner arcs bulged past the clip
                                // and were cut off, which is why the dashes
                                // stopped short of all four corners.
                                RoundedRectangle(cornerRadius: Theme.rTile, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                    .foregroundStyle(Theme.lineStrong)
                                Image(systemName: "plus")
                                    .font(.system(size: 30, weight: .light))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.gutter)
            }
            // Only up and down. A row whose contents already fit still
            // takes a sideways drag and rubber-bands, which on a page that
            // scrolls vertically reads as the page itself coming loose.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .padding(.top, 26)
        .padding(.bottom, 26)
    }

    private func tile(_ gym: Gym) -> some View {
        let counts = store.routeCount(in: gym)
        return GymTile(
            // No count under the name. A tile is a way into a gym, and how
            // many routes have been scanned there is a fact about the gym's
            // own screen, not a label the row needs to carry.
            name: gym.name,
            sent: counts.sent > 0
        ) {
            ZStack {
                Theme.surface
                if let photo = GymPicture.image(for: gym) {
                    // Fitted, because a picture cropped to a square loses the
                    // ends of it.
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                } else {
                    // The gym's own mark, the same one it wears in Explore
                    // and on its page, so a gym is one thing everywhere.
                    GymMark(name: gym.name, seed: gym.venueID ?? gym.id.uuidString, size: 128)
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
    var sub: String? = nil
    var sent: Bool = false
    @ViewBuilder var face: Face

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            face
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rTile, style: .continuous))
                // A lazy grid inside a link's label eats the tap that should
                // reach the link. The gym tiles draw their walls with one and
                // were dead as a result, while Explore, whose face is a plain
                // shape, worked. Nothing in the face needs to be touchable.
                .allowsHitTesting(false)

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
                if let sub {
                    Text(sub)
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 128, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Library card

/// One route: what you called it, how many times you have been on it, and how
/// many of those went to the top.
struct LibraryCard: View {
    let entry: LibraryEntry
    @ObservedObject private var store = Store.shared

    /// Where it was climbed, as the gym's own mark, when the climb is filed.
    private var gym: Gym? {
        guard let id = entry.latest.gymID ?? entry.attempts.compactMap(\.gymID).first else { return nil }
        return store.gyms.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClimbThumbnail(climb: entry.latest)
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let gym {
                        GymMark(name: gym.name, seed: gym.venueID ?? gym.id.uuidString, size: 26)
                            .overlay(RoundedRectangle(cornerRadius: 26 * 0.22, style: .continuous)
                                        .stroke(Theme.chalk.opacity(0.9), lineWidth: 1.5))
                            .padding(8)
                            .accessibilityLabel(gym.name)
                    }
                }
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
