import SwiftUI
import PhotosUI

/// Photographing a wall, built to the same shape as recording a climb.
///
/// The two are the same act from the person's side: point the phone at the wall,
/// frame it, press the round button. They used to look nothing alike, because
/// scanning handed off to the system camera sheet while recording had this
/// screen. Same furniture now: full bleed preview, a white capsule to get out
/// of, a round button at the bottom, and the guidance that is specific to this
/// job sitting where the recording screen puts its own.
struct WallCaptureScreen: View {
    @StateObject private var camera = StillCamera()
    @Environment(\.dismiss) private var dismiss
    @Binding var pickerItem: PhotosPickerItem?
    let onCaptured: (UIImage?) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isAvailable {
                CameraPreview(session: camera.session).ignoresSafeArea()
                framingGuide
            } else {
                unavailable
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if camera.isAvailable { controls }
        }
        .task { await camera.prepare() }
        .onDisappear { camera.teardown() }
    }

    // MARK: Framing

    private var framingGuide: some View {
        GeometryReader { geo in
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width / 3, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width / 3, y: geo.size.height))
                    p.move(to: CGPoint(x: geo.size.width * 2 / 3, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width * 2 / 3, y: geo.size.height))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                Rectangle()
                    .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 90)
            }
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                camera.teardown()
                onCaptured(nil)
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Cancel")
                        .font(Theme.ui(15, .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if camera.isAvailable {
                StatusChip(text: "Whole route in frame", dot: Theme.ok)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            // The one thing worth saying about a scan photo, and the reason a
            // shadowed wall scans badly: Trace separates holds by color.
            Text("Even light. A wall half in shadow splits one color into two.")
                .font(Theme.ui(12.5))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            ZStack {
                ShutterButton(busy: camera.isCapturing) {
                    camera.capture { image in
                        guard let image else { return }
                        camera.teardown()
                        onCaptured(image)
                        dismiss()
                    }
                }

                // The library, where the recording screen has nothing, because
                // a wall you photographed earlier is a perfectly good scan and
                // a climb you filmed earlier is imported from the panel.
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images,
                                 photoLibrary: .shared()) {
                        VStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 19, weight: .regular))
                            Text("Library")
                                .font(Theme.ui(11, .medium))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 66, height: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 26)
            }

            if let problem = camera.errorMessage {
                Text(problem)
                    .font(Theme.ui(13))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    // MARK: No camera

    private var unavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.7))

            Text(camera.isAuthorized ? "No camera here" : "Trace needs the camera")
                .font(Theme.serif(22, .semibold))
                .foregroundStyle(.white)

            Text(camera.isAuthorized
                 ? "This device has no camera Trace can use, which is always true of the Simulator. Choose a photo you already took instead."
                 : "Scanning needs permission to use the camera. You can allow it in Settings, or choose a photo you already took.")
                .font(Theme.ui(14.5))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Text("Choose a photo")
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Button {
                onCaptured(nil)
                dismiss()
            } label: {
                Text("Back")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 34)
    }
}

/// The shutter. Same size and the same ring as the record button, so the two
/// screens read as the same control doing the job each one is for.
struct ShutterButton: View {
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
                if busy {
                    ProgressView().tint(Theme.blue)
                }
            }
            // The whole circle, and a bit more. A plain button hit-tests what it
            // draws, and a ring drawn as a stroke is mostly hole.
            .frame(width: 84, height: 84)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Take the photo")
    }
}
