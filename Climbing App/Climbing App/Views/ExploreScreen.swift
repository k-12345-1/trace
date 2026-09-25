import SwiftUI
import CoreLocation

/// Climbing gyms in the United States, nearest first.
///
/// This is the one screen in Trace that is about places you have not been. Every
/// other screen is built out of what you have recorded; this one exists so that
/// a new phone with nothing on it still has something to say.
///
/// Two honesties are carried on the face of the screen rather than buried. The
/// coordinates behind the distances are city centres, so a distance is to the
/// city and not to the door. And the list is a hand-built starter set rather
/// than a survey, so it is certainly missing gyms.
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
        }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NavHeader(title: nil) { dismiss() }
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
                        .background(Theme.accent, in: Capsule())
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
            Text("No gym here matches that. The list is a starter set, so it is very likely missing yours.")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(venues) { venue in
                    row(venue)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func row(_ venue: Venue) -> some View {
        HStack(spacing: 14) {
            // The colours you have scanned there, when you have. A gym you have
            // been to should not look identical to one you have not.
            face(for: venue)

            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(venue.place)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
                if let miles = distance(to: venue) {
                    Text(miles)
                        .font(Theme.ui(12.5, .medium)).monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                }
            }
            Spacer(minLength: 8)
            if scanned(venue) != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.blue))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func face(for venue: Venue) -> some View {
        ZStack {
            Theme.surface2
            if let gym = scanned(venue), !store.routes(in: gym).isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2),
                          spacing: 2) {
                    ForEach(Array(store.routes(in: gym).prefix(4).enumerated()), id: \.offset) { _, r in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(hexString: r.colorHex))
                            .frame(height: 18)
                    }
                }
                .padding(6)
            } else {
                Text(initials(venue.name))
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.blue.opacity(0.5))
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }

    /// The gym in your own list that is this venue, if you have scanned there.
    ///
    /// Matched on the words rather than the whole string. You typed your gym's
    /// name yourself, so "Central Rock Watertown" and "Central Rock Gym
    /// Watertown" are the same place and an exact compare says they are not.
    /// Filler words are dropped so they cannot carry a match on their own.
    private func scanned(_ venue: Venue) -> Gym? {
        let wanted = Self.words(venue.name)
        guard !wanted.isEmpty else { return nil }
        return store.gyms.first { gym in
            let mine = Self.words(gym.name)
            guard !mine.isEmpty else { return false }
            // Every word of the shorter name appears in the longer one.
            return mine.isSubset(of: wanted) || wanted.isSubset(of: mine)
        }
    }

    private static let filler: Set<String> = ["gym", "the", "climbing", "center", "centre", "co"]

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

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "G" : String(letters).uppercased()
    }

    /// Said once, at the bottom, rather than implied nowhere.
    private var footnote: some View {
        Text(whereabouts.state.location == nil
             ? "A starter list rather than a survey. It covers the larger metros and the chains, and it is certainly missing gyms."
             : "Distances are to the middle of each gym's city, not to its door. A starter list rather than a survey, so it is certainly missing gyms.")
            .font(Theme.ui(12))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
    }
}
