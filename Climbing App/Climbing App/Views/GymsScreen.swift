import SwiftUI

/// Every gym you have scanned something at, and what is on the wall there.
///
/// Trace has no directory of gyms. Each one here exists because you scanned a
/// route at it, which is why the tile shows the colors on that wall rather than
/// a logo: the routes you have saved are the only picture of the place it has.
struct GymsScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    private var totals: (routes: Int, sent: Int) {
        store.routes.reduce(into: (0, 0)) { acc, route in
            acc.0 += 1
            if route.sent { acc.1 += 1 }
        }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NavHeader(title: nil) { dismiss() }
                    header

                    if store.gyms.isEmpty {
                        empty
                    } else {
                        summary
                        LazyVStack(spacing: 12) {
                            ForEach(store.gyms) { gym in
                                NavigationLink { RoutesScreen(gym: gym) } label: {
                                    GymCard(gym: gym)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { store.deleteGym(gym) } label: {
                                        Label("Delete gym and its routes", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.gutter)

                        Text("A gym is made the first time you scan a route at it. Press and hold one to remove it along with everything scanned there.")
                            .font(Theme.ui(13))
                            .foregroundStyle(Theme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your gyms")
                .font(Theme.title(30))
                .foregroundStyle(Theme.ink)
            Text(store.gyms.isEmpty
                 ? "Nothing scanned yet"
                 : "\(store.gyms.count) place\(store.gyms.count == 1 ? "" : "s") you climb")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
    }

    private var summary: some View {
        MetricStrip(items: [
            .init(value: "\(store.gyms.count)", label: "Gyms"),
            .init(value: "\(totals.routes)", label: "Routes"),
            .init(value: "\(totals.sent)", label: "Sent"),
            .init(value: "\(max(0, totals.routes - totals.sent))", label: "Open")
        ])
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .card()
        .padding(.horizontal, Theme.gutter)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("No gyms yet")
            Text("Scan a route and Trace will make the gym for you. There is no directory to join and nobody to ask.")
                .font(Theme.ui(14.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
        .padding(.horizontal, Theme.gutter)
    }
}

/// One gym: the colors on its walls, its name, and what you have done there.
private struct GymCard: View {
    let gym: Gym
    @ObservedObject private var store = Store.shared

    init(gym: Gym) { self.gym = gym }

    var body: some View {
        let routes = store.routes(in: gym)
        let counts = store.routeCount(in: gym)

        HStack(spacing: 15) {
            face(routes)

            VStack(alignment: .leading, spacing: 6) {
                Text(gym.name)
                    .font(Theme.serif(19, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text("\(counts.total) route\(counts.total == 1 ? "" : "s") · \(counts.sent) sent")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink2)
                if let last = routes.map(\.scannedAt).max() {
                    Text("Last scan \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }

    /// The wall, as far as Trace has seen it: a block of the route colors, or
    /// the gym's initials when nothing has been scanned yet.
    @ViewBuilder
    private func face(_ routes: [Route]) -> some View {
        ZStack {
            Theme.surface2
            if routes.isEmpty {
                Text(initials)
                    .font(Theme.serif(24, .semibold))
                    .foregroundStyle(Theme.blue.opacity(0.55))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3),
                                         count: 3), spacing: 3) {
                    ForEach(Array(routes.prefix(9).enumerated()), id: \.offset) { _, route in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hexString: route.colorHex))
                            .frame(height: 24)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }

    private var initials: String {
        let letters = gym.name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "G" : String(letters).uppercased()
    }
}

// MARK: - Routes in one gym

struct RoutesScreen: View {
    let gym: Gym
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let counts = store.routeCount(in: gym)
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NavHeader(title: nil) { dismiss() }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gym.name)
                            .font(Theme.title(30))
                            .foregroundStyle(Theme.ink)
                        Text("\(counts.total) scanned · \(counts.sent) sent")
                            .font(Theme.ui(14))
                            .foregroundStyle(Theme.ink3)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 12)

                    LazyVStack(spacing: 10) {
                        ForEach(store.routes(in: gym)) { route in
                            NavigationLink { RouteDetailScreen(route: route) } label: { row(route) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { store.toggleSent(route) } label: {
                                        Label(route.sent ? "Mark unsent" : "Mark sent",
                                              systemImage: route.sent ? "arrow.uturn.backward" : "checkmark")
                                    }
                                    Button(role: .destructive) { store.deleteRoute(route) } label: {
                                        Label("Delete route", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func row(_ route: Route) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hexString: route.colorHex))
                .frame(width: 8, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(route.displayName)
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 9) {
                    if !route.grade.isEmpty {
                        Text(route.grade)
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    Text("\(route.holds.count) holds")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer()
            if route.sent {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.blue))
            }
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
    }
}

// MARK: - One route

struct RouteDetailScreen: View {
    let route: Route
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    private var live: Route { store.routes.first { $0.id == route.id } ?? route }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The photograph is the header: it runs to the very top of
                    // the screen, under the status bar, with the back control
                    // floating on it. The wall is what you came to look at.
                    // The control rides on the photograph. Pinned to the screen
                    // it would float over white paper once you scrolled past.
                    photo
                        .overlay(alignment: .topLeading) {
                            BackOverlayButton { dismiss() }
                                .padding(.leading, Theme.gutter - 6)
                                .padding(.top, 52)
                        }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(live.displayName)
                                .font(Theme.title(26))
                                .foregroundStyle(Theme.ink)
                            HStack(spacing: 9) {
                                if !live.grade.isEmpty {
                                    Text(live.grade)
                                        .font(Theme.ui(13, .semibold))
                                        .foregroundStyle(Theme.accentText)
                                }
                                Text(live.scannedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(Theme.ui(13))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                        Spacer()
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(hexString: live.colorHex))
                            .frame(width: 30, height: 30)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                    MetricStrip(items: [
                        .init(value: "\(live.holds.count)", label: "Holds"),
                        .init(value: live.grade.isEmpty ? "—" : live.grade, label: "Grade"),
                        .init(value: live.sent ? "Yes" : "Not yet", label: "Sent")
                    ])
                    .padding(18)
                    .card()
                    .padding(.horizontal, Theme.gutter)

                    VStack(alignment: .leading, spacing: 14) {
                        Button { store.toggleSent(live) } label: {
                            Text(live.sent ? "Mark unsent" : "Mark sent")
                                .font(Theme.ui(16, .semibold))
                                .foregroundStyle(live.sent ? Theme.ink : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(live.sent ? Theme.surface : Theme.accent)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Text("Trace found these holds by color, not by reading the setter's intent. Anything it got wrong was dropped when you saved it.")
                            .font(Theme.ui(13))
                            .foregroundStyle(Theme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 22)
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private let photoHeight: CGFloat = 420

    @ViewBuilder
    private var photo: some View {
        if let data = try? Data(contentsOf: live.photoURL), let ui = UIImage(data: data) {
            GeometryReader { geo in
                let r = fitted(image: ui.size, in: geo.size)
                ZStack {
                    Color.black
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit)
                    ForEach(Array(live.holds.enumerated()), id: \.offset) { _, hold in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Theme.blueLight, lineWidth: 2)
                            .frame(width: hold.width * r.width + 8, height: hold.height * r.height + 8)
                            .position(x: r.minX + hold.midX * r.width, y: r.minY + hold.midY * r.height)
                    }
                }
            }
            .frame(height: photoHeight)
            .clipped()
        } else {
            missingPhoto
        }
    }

    /// No file on disk. A black rectangle reads as a broken screen, so this says
    /// what happened and leaves the rest of the route usable.
    private var missingPhoto: some View {
        ZStack {
            Theme.surface
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.ink3)
                Text("The photo for this route is gone")
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.ink2)
                Text("Its holds and color are still here.")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.top, 40)
        }
        .frame(height: 260)
    }

    private func fitted(image: CGSize, in size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let ia = image.width / image.height, va = size.width / size.height
        if va > ia {
            let w = size.height * ia
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
        let h = size.width / ia
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
}

extension Color {
    /// Parses "#RRGGBB" as written by the scanner.
    init(hexString: String) {
        let cleaned = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        self.init(hex: UInt32(cleaned, radix: 16) ?? 0x888888)
    }
}
