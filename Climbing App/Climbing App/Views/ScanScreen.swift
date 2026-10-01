import SwiftUI
import PhotosUI
import UIKit

/// Scan a route off any wall in any gym.
///
/// Photograph the wall, tap one hold of the route's color, and Trace picks out
/// everything else that color. No route database, no hold model, no gym
/// partnership: it works on the first photo you take anywhere.
struct ScanScreen: View {
    /// Set when the scan was started from a gym's own screen, so the route is
    /// filed there without being asked which gym you are standing in.
    var gym: Gym? = nil

    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var holds: [RouteScanner.Hold] = []
    @State private var dropped: Set<UUID> = []
    @State private var colorHex = "#888888"
    @State private var grades: [String] = []
    /// Holds the scan missed, pointed at by hand. Kept apart from the scanned
    /// ones so that changing colour does not throw them away.
    @State private var added: [RouteScanner.Hold] = []
    /// Every route color Trace can see on this wall, best first.
    @State private var swatches: [RouteScanner.Swatch] = []
    @State private var chosen: RouteScanner.Swatch?
    /// The start and finish stickers the photograph could read.
    @State private var tags: [RouteScanner.Tag] = []

    /// Whether the chosen route looks whole in this photograph.
    private var coverage: CoverageEngine.Coverage? {
        guard !kept.isEmpty else { return nil }
        let others = swatches.filter { $0.id != chosen?.id }.flatMap { $0.holds.map(\.rect) }
        return CoverageEngine.read(holds: kept.map(\.rect), tags: tags, others: others)
    }
    @State private var reading = false

    @State private var pickerItem: PhotosPickerItem?


    @State private var routeName = ""
    @State private var grade = ""
    @State private var gymName = ""
    @State private var selectedGym: Gym?

    private var kept: [RouteScanner.Hold] {
        (holds + added).filter { !dropped.contains($0.id) }
    }

    var body: some View {
        Group {
            if let image {
                wall(image)
            } else {
                // The camera IS this screen until there is a photo to work on.
                //
                // It used to be a cover raised over a page, and that page was
                // drawn first: a white flash, every time, before the camera came
                // up over it. There is nothing to put on that page anyway, since
                // the whole screen is about a photograph nobody has taken yet.
                WallCaptureScreen(pickerItem: $pickerItem) { picked in
                    if let picked { adopt(picked) } else { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .task {
            if let gym {
                selectedGym = gym
                gymName = gym.name
            }
        }
    }

    /// The photograph, and everything you do to it.
    private var wallBackground: some View { PaperGround() }

    private func wall(_ image: UIImage) -> some View {
        NavigationStack {
            ZStack {
                wallBackground
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Hairline()
                        stage(image)
                        controls
                        if !kept.isEmpty { Hairline(); details }
                    }
                    .holdsThePageWidth()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Scan a route")
                    .font(Theme.heading(19))
                    .foregroundStyle(Theme.ink)
                MicroLabel(text: image == nil ? "Photograph the wall" : "Pick the route's color")
            }
            Spacer()
            Button("CANCEL") { dismiss() }
                .font(Theme.mono(11, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    // MARK: The wall

    /// The photograph, at its own shape.
    ///
    /// It used to sit in a box of a fixed height with the picture fitted inside
    /// it, which put black down both sides of every portrait photo: a letterbox
    /// around the one thing on this screen worth looking at. The box now takes
    /// the picture's own aspect at the full width of the phone, so the image
    /// runs edge to edge and nothing is cropped. A tall photograph makes a tall
    /// stage, and the page scrolls, which it already did.
    private func stage(_ ui: UIImage) -> some View {
        let aspect = ui.size.height > 0 ? ui.size.width / ui.size.height : 0.75
        return GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Everything Trace thinks is on the route.
                ForEach(holds + added) { hold in
                    let dropped = self.dropped.contains(hold.id)
                    HoldOutline(outline: hold.outline, box: hold.rect, frame: rect)
                        .stroke(dropped ? Theme.ink3.opacity(0.5) : Theme.accent,
                                style: StrokeStyle(lineWidth: dropped ? 1 : 2.5, lineJoin: .round))
                        .contentShape(HoldOutline(outline: hold.outline, box: hold.rect, frame: rect))
                        .onTapGesture { toggle(hold) }
                }

            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard rect.contains(location) else { return }
                add(at: CGPoint(x: (location.x - rect.minX) / rect.width,
                                y: (location.y - rect.minY) / rect.height))
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    /// The wall's own colors, offered rather than asked for.
    ///
    /// A gym sets routes in colors. Standing at the bottom of the wall that is
    /// the first thing anybody sees, and it is the first thing this screen
    /// should show: the colors that are on this wall, with how many holds each
    /// one has. Tapping a hold still works, and is the way out when a route is
    /// set in two shades of the same green, but nobody has to start there.
    @ViewBuilder
    private var colors: some View {
        if reading {
            MicroLabel(text: "Reading the wall")
        } else if !swatches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(text: "Routes on this wall")
                // Wrapped, not a row. A real wall has ten colours on it and a
                // single row of chips either runs off the edge of the phone or
                // hides the ones that did not fit, which on this screen means
                // hiding a route.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 9,
                                             alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    ForEach(swatches) { swatch in
                        Button { pick(swatch) } label: { chip(swatch) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(swatch.holds.count) holds")
                    }
                }
            }
        }
    }

    private func chip(_ swatch: RouteScanner.Swatch) -> some View {
        let on = chosen?.id == swatch.id
        return VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: UInt32(swatch.hex.dropFirst(), radix: 16) ?? 0x888888))
                .frame(width: 42, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(on ? Theme.ink : Theme.line, lineWidth: on ? 2.5 : 1))
            Text("\(swatch.holds.count)")
                .font(Theme.mono(10.5, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.ink : Theme.ink3)
        }
        .contentShape(Rectangle())
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            colors

            HStack {
                // Not "Reading the wall" again: the colours block above says
                // that already, and it said it twice on every scan.
                if reading {
                    EmptyView()
                } else if kept.isEmpty {
                    MicroLabel(text: swatches.isEmpty
                               ? "No route colors found. Tap the holds to add them."
                               : "Pick a color above.")
                } else {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: UInt32(colorHex.dropFirst(), radix: 16) ?? 0x888888))
                            .frame(width: 13, height: 13)
                        MicroLabel(text: "\(kept.count) hold\(kept.count == 1 ? "" : "s") on this route")
                    }
                }
                Spacer()
                Button("START OVER") { startOver() }
                    .font(Theme.mono(10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink3)
            }

            // Whether the photograph has the whole route. Said once, under
            // the count, so a scan of two thirds of a boulder is not saved
            // as a boulder.
            if let sentence = coverage?.sentence {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                    Text(sentence)
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // No tolerance slider. Asking a climber to tune a colour distance
            // until their route appears is asking them to do the computer's job
            // with a control whose effect nobody can predict. The two things
            // they can actually judge are whether a box belongs to the route
            // and whether a hold was missed, so those are the two things the
            // photograph takes.
            Text("Tap a hold Trace missed to add it. Tap any box to drop a hold that is not part of the route.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: Saving

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(micro: "Save it", title: "Which gym is this?")

            if !store.gyms.isEmpty {
                // Rows drawn like the fields under them, so the list and the
                // text box read as one form rather than a box dropped into it.
                VStack(spacing: 8) {
                    ForEach(store.gyms) { gym in
                        let on = selectedGym?.id == gym.id
                        Button {
                            selectedGym = gym; gymName = ""
                        } label: {
                            HStack {
                                Text(gym.name)
                                    .font(Theme.ui(15))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Theme.blue))
                                    .opacity(on ? 1 : 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(on ? Theme.blueWash : Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                                        .stroke(on ? Theme.blue : .clear, lineWidth: 1.5))
                            .contentShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            field("New gym", text: $gymName, placeholder: "Brooklyn Boulders")
                .onChange(of: gymName) { _, v in if !v.isEmpty { selectedGym = nil } }

            field("Route", text: $routeName, placeholder: "Blue slab by the fan")

            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: "Grade")
                if !grades.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(grades.prefix(4), id: \.self) { g in
                            Button { grade = g } label: {
                                Text(g)
                                    .font(Theme.mono(11, weight: .medium))
                                    .foregroundStyle(grade == g ? Theme.ground : Theme.ink)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(grade == g ? Theme.button : Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.rSmall)
                                        .stroke(grade == g ? Color.clear : Theme.lineStrong, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Read off the tag in your photo.")
                        .font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
                }
                textField($grade, placeholder: "V4")
            }

            FlatButton(title: "Save to gym", filled: true) { save() }
                .disabled(selectedGym == nil && gymName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(selectedGym == nil && gymName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .padding(.bottom, 30)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: label)
            textField(text, placeholder: placeholder)
        }
    }

    private func textField(_ text: Binding<String>, placeholder: String) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.ink3))
            .font(Theme.body(15))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13).padding(.vertical, 12)
            // Clipped to the border's shape. Unclipped, the fill is a square
            // behind a rounded outline and its corners show as a halo.
            .background(Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
    }

    // MARK: Work

    private func adopt(_ ui: UIImage) {
        image = ui
        reset()
        guard let cg = ui.cgImage else { return }
        readTheWall(cg)
        Task {
            let found = await RouteScanner.readGrades(in: cg)
            await MainActor.run {
                grades = found
                if grade.isEmpty, let first = found.first { grade = first }
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        await MainActor.run { adopt(ui); pickerItem = nil }
    }

    /// Read the colors, then lead with the best of them.
    ///
    /// Opening straight onto the strongest route is the difference between a
    /// screen that has done something and a screen waiting to be told what to
    /// do. It is one tap to any of the others.
    private func readTheWall(_ cg: CGImage) {
        reading = true
        Task.detached {
            let found = RouteScanner.palette(in: cg)
            let stickers = await RouteScanner.readTags(in: cg)
            await MainActor.run {
                swatches = found
                tags = stickers
                reading = false
                if let first = found.first { pick(first) }
            }
        }
    }

    /// Choosing a colour shows the route that was found when the wall was
    /// read. There is no second pass, so there is nothing to wait for and
    /// nothing that can disagree with the number on the chip.
    private func pick(_ swatch: RouteScanner.Swatch) {
        chosen = swatch
        colorHex = swatch.hex
        holds = swatch.holds
        dropped = []
    }

    /// A hold the scan missed, pointed at.
    ///
    /// The blob is grown out from the tapped pixel, so a hold added by hand has
    /// the same outline as one found by the scan. When the tap grows into
    /// something that is not a hold, usually the wall itself, a plain box goes
    /// down instead: a tap that does nothing is indistinguishable from a tap
    /// that missed.
    private func add(at point: CGPoint) {
        guard let cg = image?.cgImage else { return }
        if let found = RouteScanner.hold(in: cg, at: point) {
            added.append(found)
        } else {
            let size = 0.055
            added.append(RouteScanner.Hold(
                rect: CGRect(x: point.x - size / 2, y: point.y - size / 2,
                             width: size, height: size),
                area: size * size))
        }
    }

    /// The chosen color, found again at full resolution. The swatch's own holds
    /// come from the coarse pass that read the whole wall, which is right for
    /// counting them and not good enough to draw boxes from.
    private func toggle(_ hold: RouteScanner.Hold) {
        if dropped.contains(hold.id) { dropped.remove(hold.id) } else { dropped.insert(hold.id) }
    }

    private func reset() {
        holds = []; added = []; dropped = []; chosen = nil; swatches = []
    }

    /// Back to the photograph, with the wall read again. Clearing the colors
    /// and leaving them cleared would put the screen in a state it cannot get
    /// into on its own: a photograph with nothing offered about it.
    private func startOver() {
        reset()
        if let cg = image?.cgImage { readTheWall(cg) }
    }

    private func save() {
        guard let ui = image, let data = ui.jpegData(compressionQuality: 0.72) else { return }
        let gym = selectedGym ?? store.addGym(named: gymName)
        guard let filename = try? store.saveRoutePhoto(data) else { return }

        store.save(Route(
            gymID: gym.id,
            name: routeName,
            grade: grade.trimmingCharacters(in: .whitespaces),
            colorHex: colorHex,
            photoFilename: filename,
            holds: kept.map { $0.rect },
            outlines: kept.map { $0.outline },
            continues: coverage.map { Array($0.continues) }
        ))
        dismiss()
    }
}

// MARK: - Camera stills
//
// The video capture path is built for climbs. Scanning wants one photograph.

