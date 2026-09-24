import SwiftUI

/// Routes to try next, chosen for the thing you are working on.
///
/// It only appears when it has something to say. There is no focus until Trace
/// has watched a couple of climbs, and nothing to recommend from until a wall
/// has been scanned, so an empty state here would be an apology on every launch
/// for the first week.
struct SuggestedRoutes: View {
    @ObservedObject private var store = Store.shared

    private var picks: [Recommendation] {
        RouteRecommender.suggest(routes: store.routes, focus: store.focus)
    }

    var body: some View {
        if let focus = store.focus, !focus.isResolved, !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header(focus)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(picks) { pick in
                            NavigationLink { RouteDetailScreen(route: pick.route) } label: {
                                card(pick)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                Text(picks[0].reason)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
    }

    private func header(_ focus: Focus) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionTitle("Try these")
            Text("For \(focus.kind.title.lowercased())")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func card(_ pick: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hexString: pick.route.colorHex))
                    .frame(width: 6, height: 18)
                if !pick.route.grade.isEmpty {
                    Text(pick.route.grade)
                        .font(Theme.ui(14, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
                if pick.route.sent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer(minLength: 8)

            Text(pick.route.displayName)
                .font(Theme.ui(15.5, .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(gymName(pick.route))
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)

            if let note = pick.gradeNote {
                Text(note)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.blueLight)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
        .frame(width: 168, height: 104, alignment: .topLeading)
        .padding(15)
        .card()
    }

    private func gymName(_ route: Route) -> String {
        store.gyms.first { $0.id == route.gymID }?.name ?? "Unknown gym"
    }
}
