import SwiftUI
import CoreLocation

/// Climbing gyms in the United States, nearest first.
///
/// This is the one screen in Trace that is about places you have not been. Every
/// other screen is built out of what you have recorded; this one exists so that
/// a new phone with nothing on it still has something to say.
///
/// Tapping a gym adds it to your gyms, which is the whole point of the screen:
/// it is the one place in Trace where a gym can arrive without you typing its
/// name. Adding is the only thing a tap does. Removing lives on the Gyms screen,
/// where it belongs, because deleting a gym deletes the routes scanned at it and
/// that is not a thing to put one stray tap away. The exception is a gym you
/// have just added and not yet used: with no routes to lose, a second tap takes
/// it back off, which is the undo for tapping the wrong row.
///
/// The list is OpenStreetMap, credited at the bottom as its license requires.
struct ExploreScreen: View {
    @ObservedObject private var store = Store.shared
    @StateObject private var whereabouts = Whereabouts()
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var venues: [Venue] {
        let all = GymDirectory.sorted(by: whereabouts.state.location)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.place.localizedCaseInsensitiveContains(trimmed)
            || ($0.street?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        NavHeader(title: nil) { dismiss() }
                        Spacer(minLength: 0)
                        NavigationLink {
                            GymMapScreen(venues: venues, focus: whereabouts.state.location)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Map")
                                    .font(Theme.ui(14, .semibold))
                            }
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.surface, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, Theme.gutter - 4)
                    }
                    header
                    search
                    locationRow
                    list
                    footnote
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Explore")
                .font(Theme.title(30))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
    }

    private var subtitle: String {
        switch whereabouts.state {
        case .located:  return "Climbing gyms near you"
        default:        return "\(GymDirectory.all.count) climbing gyms across the United States"
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink3)
            TextField("", text: $query,
                      prompt: Text("Gym, city or state").foregroundStyle(Theme.ink3))
                .font(Theme.ui(15))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Location

    @ViewBuilder
    private var locationRow: some View {
        switch whereabouts.state {
        case .unasked:
            prompt(title: "Put the closest ones first",
                   detail: "Trace sorts this list by how far each gym is from you. Your location is used on this phone and never leaves it.",
                   action: "Use my location") { whereabouts.find() }
        case .asking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Finding you")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
        case .denied:
            prompt(title: "Location is off for Trace",
                   detail: "The list is in alphabetical order instead. Turn location on for Trace in Settings and it will sort by how near each gym is.",
                   action: nil) { }
        case .failed:
            prompt(title: "Could not work out where you are",
                   detail: "The list is in alphabetical order instead.",
                   action: "Try again") { whereabouts.find() }
        case .located:
            EmptyView()
        }
    }

    private func prompt(title: String, detail: String,
                        action: String?, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.ui(15, .semibold))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: onTap) {
                    Text(action)
                        .font(Theme.ui(14.5, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.button, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: The list

    @ViewBuilder
    private var list: some View {
        if venues.isEmpty {
            Text("Nothing here matches that. The list is what OpenStreetMap has been told about, so it can be missing yours.")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(venues) { venue in
                    Button { tap(venue) } label: { row(venue) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func row(_ venue: Venue) -> some View {
        let gym = mine(venue)
        let routes = gym.map { store.routes(in: $0).count } ?? 0
        return HStack(spacing: 14) {
            // The colors you have scanned there, when you have. A gym you have
            // been to should not look identical to one you have not.
            face(for: venue)

            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(venue.street.map { "\($0), \(venue.place)" } ?? venue.place)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let miles = distance(to: venue) {
                        Text(miles)
                            .font(Theme.ui(12.5, .medium)).monospacedDigit()
                            .foregroundStyle(Theme.accentText)
                    }
                    // The check says it is yours. A line of prose saying the
                    // same thing is the check not being trusted to do its job.
                    // The route count stays, because that is something the mark
                    // cannot tell you.
                    if gym != nil, routes > 0 {
                        Text("\(routes) route\(routes == 1 ? "" : "s")")
                            .font(Theme.ui(12.5, .medium))
                            .foregroundStyle(Theme.blue)
                    }
                }
            }
            Spacer(minLength: 8)

            // Plus or check, so the row says what the tap will do before it is
            // tapped rather than only after.
            Image(systemName: gym == nil ? "plus" : "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gym == nil ? Theme.ink2 : .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(gym == nil ? Theme.surface2 : Theme.blue))
                // The mark is now the whole confirmation, so it has to move.
                .animation(.easeOut(duration: 0.18), value: gym != nil)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }

    /// Add, or take back an add that has cost nothing yet.
    private func tap(_ venue: Venue) {
        if let gym = mine(venue) {
            // Only ever a gym with nothing in it. A gym with routes is left
            // alone here; the gym's own screen deletes, and it asks first.
            guard store.routes(in: gym).isEmpty else { return }
            store.deleteGym(gym)
        } else {
            store.addGym(named: venue.name, venueID: venue.id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The gym's own picture if it has one, then the colors you have scanned
    /// there, then the mark Trace draws.
    ///
    /// The picture wins because it is the one thing here that is actually the
    /// gym: their logo, fetched from their own site, or a photograph of the
    /// place. A grid of hold colors is a good stand-in and a poor substitute.
    private func face(for venue: Venue) -> some View {
        Group {
            if let picture = GymPicture.image(for: mine(venue)) {
                GymPictureSquare(image: picture)
            } else if let gym = mine(venue), !store.routes(in: gym).isEmpty {
                ZStack {
                    Theme.surface2
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2),
                              spacing: 2) {
                        ForEach(Array(store.routes(in: gym).prefix(4).enumerated()), id: \.offset) { _, r in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color(hexString: r.colorHex))
                                .frame(height: 18)
                        }
                    }
                    .padding(6)
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                GymMark(name: venue.name, seed: venue.id)
            }
        }
        .allowsHitTesting(false)
    }

    /// The gym in your own list that is this venue, if you have it.
    ///
    /// Three tests, in descending order of how much they can be trusted.
    ///
    /// The id, for anything added from this screen, which is exact. Then the
    /// whole name, for a gym typed with the directory's spelling. Then a word
    /// match, because gyms typed by hand before this screen existed say things
    /// like "Central Rock Watertown" for "Central Rock Gym Watertown" and an
    /// exact compare calls those different places.
    ///
    /// The word match needs two significant words on both sides. A gym someone
    /// typed as just "Movement" is a subset of every Movement in the country,
    /// and at eight hundred venues that one loose match would light up rows all
    /// over the list.
    private func mine(_ venue: Venue) -> Gym? {
        if let byID = store.gyms.first(where: { $0.venueID == venue.id }) { return byID }
        if let byName = store.gyms.first(where: {
            $0.name.caseInsensitiveCompare(venue.name) == .orderedSame
        }) { return byName }

        let wanted = Self.words(venue.name)
        guard wanted.count >= 2 else { return nil }
        return store.gyms.first { gym in
            guard gym.venueID == nil else { return false }   // already spoken for
            let mine = Self.words(gym.name)
            guard mine.count >= 2 else { return false }
            return mine.isSubset(of: wanted) || wanted.isSubset(of: mine)
        }
    }

    private static let filler: Set<String> = ["gym", "the", "climbing", "center", "center", "co"]

    private static func words(_ name: String) -> Set<String> {
        Set(name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !filler.contains($0) })
    }

    private func distance(to venue: Venue) -> String? {
        guard let here = whereabouts.state.location else { return nil }
        let miles = venue.miles(from: here)
        return miles < 10
            ? String(format: "%.1f miles away", miles)
            : "\(Int(miles.rounded())) miles away"
    }


    /// Said once, at the bottom, rather than implied nowhere. The credit is not
    /// optional: the data is under the Open Database License, which requires it.
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gym data from OpenStreetMap contributors, under the Open Database License. Cities and states from the US Census Bureau. Taken \(GymDirectory.captured).")
            Text("OpenStreetMap is mapped by volunteers, so a gym nobody has added is not here and one that has closed may still be. Tell us what is missing and we will add it upstream.")
        }
        .font(Theme.ui(12))
        .foregroundStyle(Theme.ink3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
    }
}
