import SwiftUI
import PhotosUI

/// Every gym you have scanned something at, and what is on the wall there.
///
/// A gym is here because you added it from the directory or scanned a route at
/// it. Its square shows the picture you set, then the logo its own site
/// publishes, then the colors you have scanned on that wall: three answers to
/// "which place is this", in the order of how much each one actually knows.
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
            PaperGround()
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
                .holdsThePageWidth()
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
    @State private var scanning = false
    @State private var confirmingDelete = false
    @State private var pickingImage: PhotosPickerItem?

    var body: some View {
        let counts = store.routeCount(in: gym)
        let routes = store.routes(in: gym)
        let climbed = store.library(in: gym)
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Back on the left, remove on the right, on the same line.
                    // It was a full width button at the foot of the page, which
                    // is a lot of furniture for something you do once.
                    HStack {
                        NavHeader(title: nil) { dismiss() }
                        Spacer(minLength: 0)
                        removeGym
                    }
                    HStack(alignment: .center, spacing: 14) {
                        picture
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gym.name)
                                .font(Theme.title(26))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(subtitle(routes: routes, climbed: climbed))
                                .font(Theme.ui(14))
                                .foregroundStyle(Theme.ink3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 12)


                    // What you have actually done here comes before what is on
                    // the walls. The routes are a catalogue; the climbs are the
                    // reason you opened the gym.
                    if !climbed.isEmpty {
                        climbsHere(climbed)
                    }

                    if routes.isEmpty && climbed.isEmpty {
                        EmptyGym(gym: gym) { scanning = true }
                    } else if !routes.isEmpty {
                        SectionTitle("Routes scanned here")
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, 8)
                        LazyVStack(spacing: 10) {
                            ForEach(routes) { route in
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
                }
                .padding(.bottom, 156)
                .holdsThePageWidth()
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $scanning) { ScanScreen(gym: gym) }
        .alert("Remove \(gym.name)?", isPresented: $confirmingDelete) {
            Button("Remove", role: .destructive) { store.deleteGym(gym); dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(counts.total == 0
                 ? "Nothing has been scanned here, so nothing else goes with it."
                 : "The \(counts.total) route\(counts.total == 1 ? "" : "s") scanned here, and their photos, go with it. Your climbs and their analysis stay.")
        }
    }

    /// The gym's picture: yours if you set one, theirs otherwise, and a prompt
    /// if there is neither.
    ///
    /// Trace ships no gym logos and no longer fetches any. Theirs is the icon their own site
    /// publishes, fetched once and kept here, which is the same picture the
    /// list and the map now show. Tapping still replaces it with whatever you
    /// like: a photograph of the place, or their sign, or the view from the
    /// car park.
    private var picture: some View {
        PhotosPicker(selection: $pickingImage, matching: .images) {
            Group {
                if let photo = GymPicture.image(for: live) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                } else {
                    ZStack {
                        Theme.surface
                        VStack(spacing: 3) {
                            Image(systemName: "camera")
                                .font(.system(size: 15, weight: .regular))
                            Text("Add")
                                .font(Theme.ui(10.5, .medium))
                        }
                        .foregroundStyle(Theme.ink3)
                    }
                }
            }
            .frame(width: 66, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.lineStrong, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .onChange(of: pickingImage) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    store.setImage(data, for: gym)
                }
                pickingImage = nil
            }
        }
    }

    /// Read back out of the store so a new picture shows at once.
    private var live: Gym? { store.gyms.first { $0.id == gym.id } }

    /// The line under the gym's name, counting the things this page shows.
    ///
    /// Sent used to count scanned routes marked sent, while the list below it
    /// shows climbs, each with a tick on it. A gym with three ticked climbs and
    /// nothing scanned therefore read "0 sent" under a page full of check
    /// marks. Now it counts the ticks, and scanning is mentioned only when
    /// something has been scanned.
    private func subtitle(routes: [Route], climbed: [LibraryEntry]) -> String {
        GymSummary.line(routes: routes, climbed: climbed)
    }

    /// The routes you have filmed here, newest first.
    private func climbsHere(_ entries: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Climbs attempted")
                .padding(.horizontal, Theme.gutter)
            LazyVStack(spacing: 10) {
                ForEach(entries) { entry in
                    NavigationLink { ClimbCardScreen(entry: entry) } label: {
                        HStack(spacing: 13) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.name)
                                    .font(Theme.serif(17, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 9) {
                                    Text("\(entry.attemptCount) attempt\(entry.attemptCount == 1 ? "" : "s")")
                                        .font(Theme.ui(13))
                                        .foregroundStyle(Theme.ink3)
                                    Text(entry.lastClimbed.formatted(date: .abbreviated, time: .omitted))
                                        .font(Theme.ui(13))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            Spacer(minLength: 8)
                            if entry.sendCount > 0 {
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.bottom, 6)
    }

    /// Removing the gym lives on the gym, where you can see what is in it.
    /// Before this it was only a long press on the list, which is a gesture with
    /// nothing on screen to suggest it exists.
    ///
    /// The tap only opens the question. Nothing here deletes anything on its
    /// own, which is what makes a bare icon an acceptable control for it.
    private var removeGym: some View {
        Button { confirmingDelete = true } label: {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.ink2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.gutter - 4)
        .accessibilityLabel("Remove this gym")
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
    @State private var showLine = true

    private var live: Route { store.routes.first { $0.id == route.id } ?? route }

    var body: some View {
        ZStack {
            PaperGround()
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

                    suggestedLine

                    VStack(alignment: .leading, spacing: 14) {
                        Button { store.toggleSent(live) } label: {
                            Text(live.sent ? "Mark unsent" : "Mark sent")
                                .font(Theme.ui(16, .semibold))
                                .foregroundStyle(live.sent ? Theme.ink : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(live.sent ? Theme.surface : Theme.button)
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
                .holdsThePageWidth()
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
                let line = showLine ? LineEngine.read(holds: live.holds) : nil
                ZStack {
                    Color.black
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit)

                    // The line, drawn through the holds in the order they are
                    // met. Under the boxes, so it never hides a hold.
                    if let line {
                        Path { p in
                            let points = line.holds.map {
                                CGPoint(x: r.minX + $0.midX * r.width,
                                        y: r.minY + $0.midY * r.height)
                            }
                            guard let first = points.first else { return }
                            p.move(to: first)
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(Theme.chalk.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                                   lineJoin: .round))
                    }

                    ForEach(Array(live.holds.enumerated()), id: \.offset) { _, hold in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Theme.blueLight, lineWidth: 2)
                            .frame(width: hold.width * r.width + 8, height: hold.height * r.height + 8)
                            .position(x: r.minX + hold.midX * r.width, y: r.minY + hold.midY * r.height)
                    }

                    if let line {
                        ForEach(Array(line.holds.enumerated()), id: \.offset) { i, hold in
                            Text("\(i + 1)")
                                .font(Theme.mono(10, weight: .bold))
                                .foregroundStyle(Theme.blue)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Theme.chalk))
                                .position(x: r.minX + hold.midX * r.width,
                                          y: r.minY + hold.midY * r.height)
                        }
                    }
                }
            }
            .frame(height: photoHeight)
            .clipped()
        } else {
            missingPhoto
        }
    }

    // MARK: The line

    /// What the shape of the holds says about the way up.
    ///
    /// Deliberately called the line and not the beta. Trace has a photograph of
    /// colored blobs: it cannot see which way a hold faces, how good it is, or
    /// how steep the wall is, so it can say what order the holds go in and
    /// which gaps are long, and it cannot say which hand to use.
    @ViewBuilder
    private var suggestedLine: some View {
        if let line = LineEngine.read(holds: live.holds) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle("The line")
                    Spacer()
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showLine.toggle() } } label: {
                        Text(showLine ? "Hide on photo" : "Show on photo")
                            .font(Theme.ui(13.5, .semibold))
                            .foregroundStyle(Theme.accentText)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let summary = LineEngine.summary(line) {
                    Text(summary)
                        .font(Theme.body(14.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let notes = line.moves.compactMap { LineEngine.note(for: $0) }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(Theme.body(13.5))
                                .foregroundStyle(Theme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(LineEngine.caveat)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 20)
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


// MARK: - A gym with nothing in it yet

/// What to show on a gym you have just added.
///
/// The screen used to be the gym's name over white space, which says the app is
/// broken rather than that the gym is new. Everything here is either an action
/// or a number taken from your own climbing; there are no invented routes and no
/// claims about what this gym has on its walls, because Trace has never seen it.
private struct EmptyGym: View {
    let gym: Gym
    let onScan: () -> Void
    @ObservedObject private var store = Store.shared

    init(gym: Gym, onScan: @escaping () -> Void) {
        self.gym = gym
        self.onScan = onScan
    }

    /// The hardest thing you have sent anywhere, on whichever scale you wrote it
    /// in. Only grades on one scale are ever compared, so this picks the scale
    /// you use most and answers within it.
    private var bestSent: String? {
        let graded = store.routes.filter { $0.sent }
            .compactMap { r -> (String, Grade)? in
                Grade.parse(r.grade).map { (r.grade, $0) }
            }
        guard !graded.isEmpty else { return nil }
        let commonest = Dictionary(grouping: graded, by: { $0.1.scale })
            .max { $0.value.count < $1.value.count }?.value ?? graded
        return commonest.max { $0.1.index < $1.1.index }?.0
    }

    /// Routes you have scanned at your other gyms. Not a suggestion about this
    /// gym, and labeled as what it is.
    private var elsewhere: [Route] {
        store.routes.filter { $0.gymID != gym.id && !$0.sent }
            .sorted { $0.scannedAt > $1.scannedAt }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Nothing scanned here yet")
                Text("Photograph a wall. Trace reads the route colors on it and saves the one you pick to \(gym.name).")
                    .font(Theme.ui(14.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onScan) {
                    Text("Scan a route here")
                        .font(Theme.ui(16, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.button, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .card()

            if let best = bestSent {
                VStack(alignment: .leading, spacing: 7) {
                    SectionTitle("Where to start")
                    Text("The hardest thing you have sent is \(best). Scan something at that grade and one above it, so there is a route here you can finish and one you cannot yet.")
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .card()
            }

            if !elsewhere.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Still open at your other gyms")
                    Text("Not here, and not a suggestion about this wall. Trace has never seen \(gym.name).")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(elsewhere) { route in
                        NavigationLink { RouteDetailScreen(route: route) } label: {
                            HStack(spacing: 11) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color(hexString: route.colorHex))
                                    .frame(width: 6, height: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.displayName)
                                        .font(Theme.ui(15, .semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Text(store.gyms.first { $0.id == route.gymID }?.name ?? "")
                                        .font(Theme.ui(12.5))
                                        .foregroundStyle(Theme.ink3)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                if !route.grade.isEmpty {
                                    Text(route.grade)
                                        .font(Theme.ui(13, .semibold))
                                        .foregroundStyle(Theme.accentText)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .card()
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}
