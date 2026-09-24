import SwiftUI

/// Every gym you have scanned something at, and what is on the wall there.
struct GymsScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavHeader { dismiss() }
                    VStack(alignment: .leading, spacing: 6) {
                        MicroLabel(text: "Your gyms")
                        Text(store.gyms.isEmpty ? "Nothing scanned yet" : "Where you climb")
                            .font(Theme.heading(22))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
                    Hairline()

                    if store.gyms.isEmpty {
                        Text("Scan a route and Trace will make the gym for you. There is no directory to join and nobody to ask.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(20)
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(store.gyms) { gym in
                                NavigationLink { RoutesScreen(gym: gym) } label: { row(gym) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { store.deleteGym(gym) } label: {
                                            Label("Delete gym and its routes", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .background(Theme.line)
                        .padding(.bottom, 40)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func row(_ gym: Gym) -> some View {
        let counts = store.routeCount(in: gym)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(gym.name).font(Theme.heading(16)).foregroundStyle(Theme.ink)
                Text("\(counts.total) route\(counts.total == 1 ? "" : "s") · \(counts.sent) sent")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer()
            // Colour of the routes on the wall, at a glance.
            HStack(spacing: 3) {
                ForEach(Array(store.routes(in: gym).prefix(6).enumerated()), id: \.offset) { _, route in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hexString: route.colorHex))
                        .frame(width: 8, height: 14)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(Theme.ground)
        .contentShape(Rectangle())
    }
}

// MARK: - Routes in one gym

struct RoutesScreen: View {
    let gym: Gym
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavHeader { dismiss() }
                    VStack(alignment: .leading, spacing: 6) {
                        MicroLabel(text: "\(store.routeCount(in: gym).total) scanned · \(store.routeCount(in: gym).sent) sent")
                        Text(gym.name).font(Theme.heading(22)).foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
                    Hairline()

                    LazyVStack(spacing: 1) {
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
                    .background(Theme.line)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func row(_ route: Route) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hexString: route.colorHex))
                .frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(route.displayName).font(Theme.heading(16)).foregroundStyle(Theme.ink)
                HStack(spacing: 9) {
                    if !route.grade.isEmpty {
                        Text(route.grade).font(Theme.mono(10.5)).foregroundStyle(Theme.accentText)
                    }
                    Text("\(route.holds.count) holds")
                        .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                }
            }
            Spacer()
            if route.sent {
                MicroLabel(text: "Sent", color: Theme.ok)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 15)
        .background(Theme.ground)
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
                    NavHeader { dismiss() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(live.displayName).font(Theme.heading(19)).foregroundStyle(Theme.ink)
                            HStack(spacing: 9) {
                                if !live.grade.isEmpty {
                                    Text(live.grade).font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                                }
                                MicroLabel(text: live.scannedAt.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hexString: live.colorHex))
                            .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)

                    photo
                    Hairline()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            MicroLabel(text: "\(live.holds.count) holds found")
                            Spacer()
                            MicroLabel(text: live.colorHex)
                        }
                        Button { store.toggleSent(live) } label: {
                            Text((live.sent ? "Mark unsent" : "Mark sent").uppercased())
                                .font(Theme.mono(11, weight: .medium)).tracking(1.3)
                                .foregroundStyle(live.sent ? Theme.ink : Theme.ground)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(live.sent ? Color.clear : Theme.accent)
                                .overlay(RoundedRectangle(cornerRadius: Theme.r)
                                    .stroke(live.sent ? Theme.lineStrong : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Text("Trace found these holds by colour, not by reading the setter's intent. Anything it got wrong was dropped when you saved it.")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 22)
                }
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var photo: some View {
        if let data = try? Data(contentsOf: live.photoURL), let ui = UIImage(data: data) {
            GeometryReader { geo in
                let r = fitted(image: ui.size, in: geo.size)
                ZStack {
                    Color.black
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit)
                    ForEach(Array(live.holds.enumerated()), id: \.offset) { _, hold in
                        Rectangle()
                            .stroke(Theme.accent, lineWidth: 2)
                            .frame(width: hold.width * r.width + 8, height: hold.height * r.height + 8)
                            .position(x: r.minX + hold.midX * r.width, y: r.minY + hold.midY * r.height)
                    }
                }
            }
            .frame(height: 400)
            .clipped()
        } else {
            Color.black.frame(height: 200)
                .overlay(MicroLabel(text: "Photo missing"))
        }
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
