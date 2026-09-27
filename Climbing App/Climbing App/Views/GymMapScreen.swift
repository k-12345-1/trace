import SwiftUI
import MapKit

/// Where every gym in the directory actually is.
///
/// The list answers "what is near me". This answers "where are they", which is
/// a different question and the one you ask when you are deciding where to
/// drive. Pins are the buildings, not the cities: that stopped being an
/// approximation when the directory moved to OpenStreetMap.
///
/// Nothing here is fetched. The map tiles come from MapKit, which is Apple's
/// business and the one network call in this screen, and the gyms come from the
/// file in the bundle.
struct GymMapScreen: View {
    /// What to show. Handed in rather than recomputed so the map and the list
    /// behind it are always looking at the same set.
    let venues: [Venue]
    let focus: CLLocation?

    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: Venue?

    /// Every gym in the directory, not the nearest few.
    ///
    /// This was capped at two hundred and fifty on the reasoning that a map
    /// with six hundred pins is a map of nothing. That is true of six hundred
    /// labelled pins, which is what it drew: each one a rounded plaque with a
    /// name on it, and the country disappearing under them. It is not true of
    /// six hundred dots. At the scale where they crowd, the crowding is the
    /// information, which is the map anyone actually wants of where climbing
    /// gyms are.
    private var shown: [Venue] { venues }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera, selection: Binding(
                get: { selected?.id },
                set: { id in selected = shown.first { $0.id == id } }
            )) {
                ForEach(shown) { venue in
                    Annotation(venue.name, coordinate: venue.coordinate) {
                        dot(venue)
                    }
                    .annotationTitles(.hidden)
                    .tag(venue.id)
                }
                if focus != nil { UserAnnotation() }
            }
            // No recentre arrow. The map already opens on you when it knows
            // where you are, and the control sat in the one corner the count
            // was in, on top of the only thing up there worth reading.
            .mapControls { MapCompass() }
            // The tiles run to the bottom of the phone; what sits on top of
            // them does not. Apple's attribution has to stay legible, and the
            // bar floats over the last ninety points of the screen, so the
            // map's own furniture is told the screen ends above it. The order
            // matters: the padding has to reach the map, and ignoring the safe
            // area afterwards is what lets the tiles still fill the glass.
            .safeAreaPadding(.bottom, 92)
            .ignoresSafeArea()

            topBar
        }
        .safeAreaInset(edge: .bottom) {
            if let selected { card(selected) }
        }
        .toolbar(.hidden, for: .navigationBar)
        // The map is the screen. Without this the bar's backdrop paints over
        // its bottom hundred and thirty points.
        .runsUnderTheBar()
        .reachesTheTop()
        .onAppear(perform: frame)
    }

    /// One gym. A dot rather than a pin with a label on it: at country scale
    /// the label is what makes six hundred of these unreadable, and the name is
    /// a tap away in the card.
    ///
    /// The one you have added is the darker blue, so your own gyms stand out of
    /// the field without a second hue being introduced to say so.
    private func dot(_ venue: Venue) -> some View {
        let isMine = mine(venue) != nil
        let isOpen = selected?.id == venue.id
        return Circle()
            .fill(isMine ? Theme.blue : Theme.blueLight)
            .frame(width: isOpen ? 17 : 11, height: isOpen ? 17 : 11)
            .overlay(Circle().stroke(.white, lineWidth: isOpen ? 2.5 : 1.5))
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
            // A dot eleven points across is not a target. The shape that takes
            // the tap is the one drawn here, so it is given the room a finger
            // needs without being given the ink.
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: isOpen)
    }

    // MARK: Framing

    /// Open on you when Trace knows where you are, and on the whole country
    /// when it does not.
    private func frame() {
        if let focus {
            camera = .region(MKCoordinateRegion(
                center: focus.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)))
        } else {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 48, longitudeDelta: 55)))
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("List")
                        .font(Theme.ui(15, .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(shown.count) gym\(shown.count == 1 ? "" : "s")")
                .font(Theme.ui(12.5, .medium))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: The selected gym

    private func card(_ venue: Venue) -> some View {
        let gym = mine(venue)
        return HStack(spacing: 14) {
            if let picture = GymPicture.image(for: gym) {
                GymPictureSquare(image: picture, size: 46)
            } else {
                GymMark(name: venue.name, seed: venue.id, size: 46)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(venue.street.map { "\($0), \(venue.place)" } ?? venue.place)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(2)
                if let miles = distance(to: venue) {
                    Text(miles)
                        .font(Theme.ui(12.5, .medium)).monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                }
            }
            Spacer(minLength: 6)

            Button {
                if let gym {
                    guard store.routes(in: gym).isEmpty,
                          store.climbs(in: gym).isEmpty else { return }
                    store.deleteGym(gym)
                } else {
                    store.addGym(named: venue.name, venueID: venue.id)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: gym == nil ? "plus" : "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gym == nil ? Theme.ink2 : .white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(gym == nil ? Theme.surface2 : Theme.blue))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(gym == nil ? "Add to your gyms" : "In your gyms")
        }
        .padding(14)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .padding(.horizontal, 14)
        // Clear of the floating bar, which this screen now runs underneath.
        .padding(.bottom, 96)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func mine(_ venue: Venue) -> Gym? {
        store.gyms.first { $0.venueID == venue.id }
            ?? store.gyms.first { $0.name.caseInsensitiveCompare(venue.name) == .orderedSame }
    }

    private func distance(to venue: Venue) -> String? {
        guard let focus else { return nil }
        let miles = venue.miles(from: focus)
        return miles < 10
            ? String(format: "%.1f miles away", miles)
            : "\(Int(miles.rounded())) miles away"
    }
}

/// The mark Trace draws for a gym.
///
/// It is a monogram on a tint taken from the gym's own id, and it is **not the
/// gym's logo**. Trace has no logos: they are trademarks belonging to the gyms,
/// there is no licensed source for six hundred of them, and fetching each one
/// from its own website would mean telling six hundred servers that someone
/// opened this app, which is the opposite of what Trace promises.
///
/// So this does the one job a logo would do here, which is to make a row
/// recognizable at a glance, without pretending to be something it is not. The
/// tint is deterministic, so a gym looks the same every time you see it, and it
/// stays inside the app's own blue ramp rather than inventing a brand color.
struct GymMark: View {
    let name: String
    let seed: String
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            tint
            Text(initials)
                .font(Theme.serif(size * 0.33, .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    /// Pure, and therefore testable: the two decisions this view makes.
    var tintForTesting: Int { tintIndex }
    var initialsForTesting: String { initials }

    private var tintIndex: Int {
        let h = abs(seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) })
        return h % 3
    }

    /// One of the ramp's darker steps, chosen by the id so it never changes.
    private var tint: Color {
        Array(Theme.ember.suffix(3))[tintIndex]
    }

    private var initials: String {
        let letters = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { !["the", "a", "of", "at"].contains($0.lowercased()) }
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "G" : String(letters).uppercased()
    }
}
