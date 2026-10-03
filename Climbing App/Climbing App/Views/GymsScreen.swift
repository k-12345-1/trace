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
    private var markSeed: String { (live ?? gym).venueID ?? gym.id.uuidString }

    private var picture: some View {
        PhotosPicker(selection: $pickingImage, matching: .images) {
            Group {
                if let photo = GymPicture.image(for: live) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                } else {
                    // The same mark the gym wears in Explore, so the page
                    // and the row are recognisably one place. Tapping still
                    // puts a photograph here instead.
                    GymMark(name: (live ?? gym).name, seed: markSeed, size: 66)
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

    /// The routes you have filmed here, newest first, as the library shows
    /// them: a still from the clip with the count on it. They were rows of
    /// text here and video cards on the home page, two faces for one thing.
    private func climbsHere(_ entries: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Climbs attempted")
                .padding(.horizontal, Theme.gutter)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                GridItem(.flexible(), spacing: 13)], spacing: 16) {
                ForEach(entries) { entry in
                    NavigationLink { ClimbCardScreen(entry: entry) } label: {
                        LibraryCard(entry: entry)
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
    @State private var showNumbers = true
    /// The boxes round the holds. Off while the figure climbs, because the
    /// body standing on a hold says where it is better than a box does.
    @State private var showBoxes = true
    @State private var showFigure = false
    @State private var figureT = 0.0
    @State private var figurePlaying = false
    @State private var confirmingDelete = false

    private var live: Route { store.routes.first { $0.id == route.id } ?? route }
    @State private var looksLike: String?
    /// The line and the planned sequence, read once per route rather than
    /// once per place on the page that draws them. The plan is a search
    /// and on a route of twenty holds it takes a second or two.
    @State private var planned: (line: LineEngine.Line, seq: BetaEngine.Sequence?)?
    private var line: LineEngine.Line? { planned?.line }
    private var seq: BetaEngine.Sequence? { planned?.seq }
    private var planKey: String { "\(live.holds.count)-\(live.startHolds ?? [])-\(live.finishHolds ?? [])" }

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
                                if let looksLike {
                                    Text(looksLike)
                                        .font(Theme.ui(13))
                                        .foregroundStyle(Theme.ink2)
                                }
                                if let edges = live.continues, !edges.isEmpty,
                                   let note = CoverageEngine.Coverage(continues: Set(edges), sawStart: false,
                                                                      sawFinish: false, tagsRead: false).sentence {
                                    Text(note)
                                        .font(Theme.ui(13))
                                        .foregroundStyle(Theme.ink2)
                                        .fixedSize(horizontal: false, vertical: true)
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

                        // Deleting lived in a long press on the gym page's
                        // row, where nobody found it. It belongs here, on
                        // the route, with a confirmation.
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete this route", systemImage: "trash")
                                .font(Theme.ui(15, .semibold))
                                .foregroundStyle(Theme.ink2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .alert("Delete \(live.displayName)?", isPresented: $confirmingDelete) {
                            Button("Delete", role: .destructive) { store.deleteRoute(live); dismiss() }
                            Button("Keep", role: .cancel) {}
                        } message: {
                            Text("The scan and its photo go. Climbs you recorded on it stay.")
                        }

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
        .reachesTheTop()
        .task(id: planKey) {
            // Off the main thread: the search is the slow part of the page.
            let holds = live.holds, starts = live.startHolds ?? [], finishes = live.finishHolds ?? []
            let shape = store.figureShape
            let photoPath = live.photoURL.path, outlines = live.outlines ?? []
            let result = await Task.detached(priority: .userInitiated) { () -> (LineEngine.Line, BetaEngine.Sequence?)? in
                guard let l = LineEngine.read(holds: holds, starts: starts, finishes: finishes, outlines: outlines) else { return nil }
                // The wall's height in the picture sizes the climber: from
                // the top edge to the mat where both were found, the whole
                // picture otherwise.
                var wallHeight: Double?
                var mat: Double?
                if let cg = UIImage(contentsOfFile: photoPath)?.upright.cgImage,
                   let bmp = Bitmap(cg, targetWidth: RouteScanner.workingWidth) {
                    let r = FaceEngine.read(in: bmp)
                    let mid = Double(bmp.width) / 2, h = Double(bmp.height)
                    let top = r.top?.y(atX: mid).map { max(0, $0 / h) } ?? 0
                    let floor = r.floor?.y(atX: mid).map { min(1, $0 / h) } ?? 1
                    wallHeight = floor - top
                    if r.floor != nil { mat = floor }
                }
                return (l, BetaEngine.read(line: l, shape: shape, wallHeight: wallHeight, mat: mat))
            }.value
            planned = result
        }
        .task {
            guard let image = UIImage(contentsOfFile: live.photoURL.path)?.cgImage else { return }
            let colour = Lab(hexString: live.colorHex), holds = live.holds, p = store.holdPrototypes
            let features = await Task.detached(priority: .utility) {
                HoldShapeEngine.features(of: holds, colour: colour, in: image)
            }.value
            looksLike = HoldShapeEngine.guess(features, prototypes: p, grade: Grade.parse(live.grade)).sentence
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    /// The photo fills the width. Its height follows its own shape, capped so
    /// the route's name and line are still reachable without a long scroll;
    /// past the cap the picture crops top and bottom rather than leaving the
    /// black bars it used to leave at the sides.
    private var photoHeight: CGFloat {
        guard let data = try? Data(contentsOf: live.photoURL), let ui = UIImage(data: data),
              ui.size.width > 0 else { return 420 }
        let w = UIScreen.main.bounds.width
        return min(w * ui.size.height / ui.size.width, UIScreen.main.bounds.height * 0.72)
    }

    @ViewBuilder
    private var photo: some View {
        if let data = try? Data(contentsOf: live.photoURL), let ui = UIImage(data: data) {
            GeometryReader { geo in
                let r = filled(image: ui.size, in: geo.size)
                let line = showLine ? self.line : nil
                ZStack {
                    Color.black
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // The line, drawn through the holds in the order they are
                    // met. Under the boxes, so it never hides a hold.
                    if let line {
                        Path { p in
                            // Through the hand holds in the order the plan
                            // uses them, or by height when there is no plan.
                            let plan = seq?.plan
                            let points = (plan.map { $0.handOrder.map { line.holds[$0] } } ?? line.hands).map {
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

                    if showBoxes {
                        let ink = RouteInk(hex: live.colorHex)
                        ForEach(Array(live.holds.enumerated()), id: \.offset) { i, hold in
                            let shape = HoldOutline(outline: live.outline(at: i) ?? [], box: hold, frame: r)
                            shape.stroke(ink.casing, style: StrokeStyle(lineWidth: 4.5, lineJoin: .round))
                                .overlay(shape.stroke(ink.color, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round)))
                        }
                    }

                    if let line, showNumbers {
                        // Every hold the plan uses, numbered in the order a
                        // limb first takes it: hand holds in a solid disc,
                        // foot holds in a ring. A hold the plan never uses
                        // has no number.
                        let plan = seq?.plan
                        let handSet = Set(line.hands)
                        ForEach(Array(line.holds.enumerated()), id: \.offset) { i, hold in
                            let number = plan.map { $0.order.firstIndex(of: i) } ?? line.hands.firstIndex(of: hold)
                            if let number {
                                let isHand = handSet.contains(hold)
                                Text("\(number + 1)")
                                    .font(Theme.mono(10, weight: .bold))
                                    .foregroundStyle(isHand ? Theme.blue : Theme.chalk)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(isHand ? Theme.chalk : Theme.blue.opacity(0.75)))
                                    .position(x: r.minX + hold.midX * r.width,
                                              y: r.minY + hold.midY * r.height)
                            } else if !handSet.contains(hold) {
                                Circle()
                                    .stroke(Theme.chalk.opacity(0.9), lineWidth: 2)
                                    .frame(width: 10, height: 10)
                                    .position(x: r.minX + hold.midX * r.width, y: r.minY + hold.midY * r.height)
                            }
                        }
                    }

                    // The figure, over everything, at wherever the scrubber is.
                    if showFigure, let seq, let pose = seq.pose(at: figureT) {
                        BetaFigure(pose: pose, rect: r, span: seq.span, shape: seq.shape)
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
        if let line {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    SectionTitle("The line")
                    Spacer()
                    // Three switches as glyphs, not three sentences: the
                    // row of words wrapped onto three lines beside the
                    // title and read as a wall of text.
                    HStack(spacing: 8) {
                        lineToggle("rectangle.dashed", on: showBoxes,
                                   label: showBoxes ? "Hide boxes" : "Show boxes") { showBoxes.toggle() }
                        lineToggle("number", on: showNumbers && showLine,
                                   label: showNumbers ? "Hide numbers" : "Show numbers") { showNumbers.toggle() }
                            .disabled(!showLine)
                        lineToggle(showLine ? "eye" : "eye.slash", on: showLine,
                                   label: showLine ? "Hide on photo" : "Show on photo") { showLine.toggle() }
                    }
                }

                // Climb it: a figure moved through the stances. Off by default,
                // because it is a drawing of one shape and not the beta, and it
                // says so where it is switched on.
                if let seq {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFigure.toggle()
                                // The boxes go when the climber arrives and
                                // come back when it leaves; either can be
                                // overridden with the button above.
                                showBoxes = !showFigure
                                if showFigure { showLine = true; figureT = 0; figurePlaying = true }
                                else { figurePlaying = false }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "figure.climbing")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(showFigure ? "Hide the climber" : "Climb it")
                                    .font(Theme.ui(14, .semibold))
                            }
                            .foregroundStyle(showFigure ? Theme.ink : .white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(showFigure ? Theme.surface2 : Theme.button, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        if showFigure {
                            BetaScrubber(t: $figureT, playing: $figurePlaying,
                                         stances: seq.stances.count)
                            Text(BetaEngine.caveat)
                                .font(Theme.ui(12))
                                .foregroundStyle(Theme.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let summary = LineEngine.summary(line) {
                    Text(summary)
                        .font(Theme.body(14.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let steps = seq?.plan.map { BetaEngine.describe($0, line: line) } ?? LineEngine.sequence(line)
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                            Text(step)
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

    private func lineToggle(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Theme.accentText : Theme.ink3)
                .frame(width: 34, height: 34)
                .background(Circle().fill(on ? Theme.accent.opacity(0.1) : Theme.surface2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

    /// Where the photo sits when it fills the frame and crops: the opposite
    /// branch of fitting. The holds, the line and the figure are all placed
    /// with this, so they land on the picture that is actually shown.
    private func filled(image: CGSize, in size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let ia = image.width / image.height, va = size.width / size.height
        if va < ia {
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
