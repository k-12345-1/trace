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
    @State private var tolerance: Double = 30
    @State private var sample: CGPoint?
    @State private var scanning = false
    /// Every route color Trace can see on this wall, best first.
    @State private var swatches: [RouteScanner.Swatch] = []
    @State private var chosen: RouteScanner.Swatch?
    @State private var reading = false

    @State private var pickerItem: PhotosPickerItem?


    @State private var routeName = ""
    @State private var grade = ""
    @State private var gymName = ""
    @State private var selectedGym: Gym?

    private var kept: [RouteScanner.Hold] { holds.filter { !dropped.contains($0.id) } }

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

    private func stage(_ ui: UIImage) -> some View {
        GeometryReader { geo in
            let rect = fitted(image: ui.size, in: geo.size)
            ZStack {
                Color.black
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // Everything Trace thinks is on the route.
                ForEach(holds) { hold in
                    let dropped = self.dropped.contains(hold.id)
                    Rectangle()
                        .stroke(dropped ? Theme.ink3.opacity(0.5) : Theme.accent,
                                lineWidth: dropped ? 1 : 2)
                        .frame(width: hold.rect.width * rect.width + 8,
                               height: hold.rect.height * rect.height + 8)
                        .position(x: rect.minX + hold.rect.midX * rect.width,
                                  y: rect.minY + hold.rect.midY * rect.height)
                        .onTapGesture { toggle(hold) }
                }

                if let s = sample {
                    Circle()
                        .stroke(Theme.chalk, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .position(x: rect.minX + s.x * rect.width,
                                  y: rect.minY + s.y * rect.height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard rect.contains(location) else { return }
                let p = CGPoint(x: (location.x - rect.minX) / rect.width,
                                y: (location.y - rect.minY) / rect.height)
                sample = p
                chosen = nil
                run(sample: p)
            }
        }
        .frame(height: 380)
        .clipped()
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
                HStack(spacing: 9) {
                    ForEach(swatches) { swatch in
                        Button { pick(swatch) } label: { chip(swatch) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(swatch.holds.count) holds")
                    }
                    Spacer(minLength: 0)
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

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            colors

            HStack {
                if scanning || reading {
                    MicroLabel(text: "Reading the wall")
                } else if holds.isEmpty {
                    MicroLabel(text: swatches.isEmpty
                               ? "No route colors found. Tap a hold instead."
                               : "Pick a color above, or tap a hold.")
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

            if sample != nil || chosen != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        MicroLabel(text: "Color range")
                        Spacer()
                        Text(String(format: "%.0f", tolerance))
                            .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                    }
                    Slider(value: $tolerance, in: 12...60, step: 1)
                        .tint(Theme.accent)
                        .onChange(of: tolerance) { _, _ in
                            if let s = sample { run(sample: s) }
                            else if let chosen { run(color: chosen) }
                        }
                    Text("Widen this if holds are missing, tighten it if the wall itself is being picked up. Tap any box to drop a hold that is not part of the route.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: Saving

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(micro: "Save it", title: "Which gym is this?")

            if !store.gyms.isEmpty {
                VStack(spacing: 1) {
                    ForEach(store.gyms) { gym in
                        Button {
                            selectedGym = gym; gymName = ""
                        } label: {
                            HStack {
                                Text(gym.name)
                                    .font(Theme.body(14.5))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if selectedGym?.id == gym.id {
                                    MicroLabel(text: "Selected", color: Theme.accentText)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(selectedGym?.id == gym.id ? Theme.surface2 : Theme.surface)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.line)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
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
            await MainActor.run {
                swatches = found
                reading = false
                if let first = found.first { pick(first) }
            }
        }
    }

    private func pick(_ swatch: RouteScanner.Swatch) {
        chosen = swatch
        sample = nil
        colorHex = swatch.hex
        // The slider starts where this color's own reach ends, which is as wide
        // as it can go without taking in the route next to it. Moving it is
        // still the way to argue with that.
        tolerance = swatch.reach
        run(color: swatch)
    }

    /// The chosen color, found again at full resolution. The swatch's own holds
    /// come from the coarse pass that read the whole wall, which is right for
    /// counting them and not good enough to draw boxes from.
    private func run(color swatch: RouteScanner.Swatch) {
        guard let cg = image?.cgImage,
              let index = swatches.firstIndex(of: swatch) else { return }
        scanning = true
        let tol = tolerance
        let all = swatches
        Task.detached {
            // The whole palette, not just the one color, so the full resolution
            // pass divides the wall exactly the way the chips did.
            let found = RouteScanner.detectHolds(in: cg, palette: all, index: index,
                                                 tolerance: tol)
            await MainActor.run {
                holds = found
                dropped = []
                scanning = false
            }
        }
    }

    private func run(sample p: CGPoint) {
        guard let cg = image?.cgImage else { return }
        scanning = true
        let tol = tolerance
        Task.detached {
            let result = RouteScanner.detectHolds(in: cg, sample: p, tolerance: tol)
            await MainActor.run {
                holds = result.holds
                colorHex = result.colorHex
                dropped = []
                scanning = false
            }
        }
    }

    private func toggle(_ hold: RouteScanner.Hold) {
        if dropped.contains(hold.id) { dropped.remove(hold.id) } else { dropped.insert(hold.id) }
    }

    private func reset() {
        holds = []; dropped = []; sample = nil; chosen = nil; swatches = []
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
            holds: kept.map { $0.rect }
        ))
        dismiss()
    }
}

// MARK: - Camera stills
//
// The video capture path is built for climbs. Scanning wants one photograph.

