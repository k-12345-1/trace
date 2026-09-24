import SwiftUI

/// Every route you have scanned, anywhere, in one list.
///
/// Explore is not a directory of the world's gyms. Trace has no such thing, and
/// pretending otherwise would be a promise it cannot keep. It is your own wall
/// collection, across every gym, filterable by what you have not sent yet.
struct ExploreScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var unsentOnly = false

    private var routes: [Route] {
        store.routes
            .filter { !unsentOnly || !$0.sent }
            .sorted { $0.scannedAt > $1.scannedAt }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if routes.isEmpty {
                        Text(store.routes.isEmpty
                             ? "Nothing scanned yet. Photograph a wall, tap one hold, and Trace picks out the rest of the route by colour."
                             : "Everything you have scanned is sent. Nothing left on this list.")
                            .font(Theme.ui(15))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Theme.gutter)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(routes) { route in
                                NavigationLink { RouteDetailScreen(route: route) } label: { row(route) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore")
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.ink)
                Text("\(store.routes.count) scanned · \(store.gyms.count) gym\(store.gyms.count == 1 ? "" : "s")")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.ink3)
            }
            Toggle(isOn: $unsentOnly) {
                Text("Only what I have not sent")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.ink2)
            }
            .tint(Theme.accent)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 20)
    }

    private func row(_ route: Route) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hexString: route.colorHex))
                .frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(route.displayName)
                    .font(Theme.serif(18, .semibold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 7) {
                    if !route.grade.isEmpty {
                        Text(route.grade)
                            .font(Theme.ui(13.5, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.ink2)
                        Text("·").foregroundStyle(Theme.ink3)
                    }
                    Text(gymName(for: route))
                        .font(Theme.ui(13.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            if route.sent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .card()
        .contentShape(Rectangle())
    }

    private func gymName(for route: Route) -> String {
        store.gyms.first { $0.id == route.gymID }?.name ?? "Unknown gym"
    }
}
