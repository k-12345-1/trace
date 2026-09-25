import SwiftUI
import PhotosUI
import UIKit

/// Scan a route off any wall in any gym.
///
/// Photograph the wall, tap one hold of the route's colour, and Trace picks out
/// everything else that colour. No route database, no hold model, no gym
/// partnership: it works on the first photo you take anywhere.
struct ScanScreen: View {
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

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    @State private var routeName = ""
    @State private var grade = ""
    @State private var gymName = ""
    @State private var selectedGym: Gym?

    private var kept: [RouteScanner.Hold] { holds.filter { !dropped.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Hairline()
                        if let image {
                            stage(image)
                            controls
                            if !kept.isEmpty { Hairline(); details }
                        } else {
                            sourcePicker
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraStillPicker { picked in
                showCamera = false
                if let picked { adopt(picked) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Scan a route")
                    .font(Theme.heading(19))
                    .foregroundStyle(Theme.ink)
                MicroLabel(text: image == nil ? "Photograph the wall" : "Tap a hold on the route")
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

    // MARK: Choosing a photo

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatButton(title: "Take a photo", filled: true) { showCamera = true }

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Text("CHOOSE FROM LIBRARY")
                    .font(Theme.mono(11, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: Theme.r)
                        .stroke(Theme.lineStrong, lineWidth: 1))
            }

            Text("Stand back far enough to get the whole route in one frame. Even light helps: Trace separates holds by color, so a photo half in shadow will split one color into two.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
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
                run(sample: p)
            }
        }
        .frame(height: 380)
        .clipped()
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
            HStack {
                if scanning {
                    MicroLabel(text: "Reading the wall")
                } else if holds.isEmpty {
                    MicroLabel(text: sample == nil
                               ? "Tap a hold on the route"
                               : "Nothing found. Try a wider colour range.")
                } else {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: UInt32(colorHex.dropFirst(), radix: 16) ?? 0x888888))
                            .frame(width: 13, height: 13)
                        MicroLabel(text: "\(kept.count) hold\(kept.count == 1 ? "" : "s") on this route")
                    }
                }
                Spacer()
                Button("START OVER") { reset() }
                    .font(Theme.mono(10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink3)
            }

            if sample != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        MicroLabel(text: "Colour range")
                        Spacer()
                        Text(String(format: "%.0f", tolerance))
                            .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                    }
                    Slider(value: $tolerance, in: 12...60, step: 1)
                        .tint(Theme.accent)
                        .onChange(of: tolerance) { _, _ in
                            if let s = sample { run(sample: s) }
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
                                    .background(grade == g ? Theme.accent : Color.clear)
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
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.r).stroke(Theme.lineStrong, lineWidth: 1))
    }

    // MARK: Work

    private func adopt(_ ui: UIImage) {
        image = ui
        reset()
        guard let cg = ui.cgImage else { return }
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
        holds = []; dropped = []; sample = nil
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

struct CameraStillPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPicked(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPicked(nil) }
    }
}
