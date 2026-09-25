import SwiftUI

/// Guided capture. Constraining the setup is a feature, not a limitation: every
/// posture metric depends on a known viewing angle, so telling you where to put
/// the phone is what makes the numbers afterwards worth reading.
struct CaptureScreen: View {
    @StateObject private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss
    let onFinish: (URL?) -> Void

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
        // Insets rather than a stack of siblings. The controls are then always
        // above the preview and always inside the safe area, neither of which
        // is left to the order things happen to be written in.
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if camera.isAvailable { controls }
        }
        .task { await camera.prepare() }
        .onDisappear { camera.teardown() }
    }

    // MARK: Framing guide

    private var framingGuide: some View {
        GeometryReader { geo in
            ZStack {
                // Rule of thirds, so the climber can be kept centered and whole.
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
            // This screen is black, and every color on it used to come from
            // the light-ground palette: Cancel was navy ink on black, which is
            // to say invisible.
            Button {
                camera.teardown()
                onFinish(nil)
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

            if camera.isRecording {
                StatusChip(text: String(format: "REC  %.1f s", camera.elapsed), dot: Theme.accent)
            } else if camera.isAvailable {
                StatusChip(text: "Whole boulder in frame", dot: Theme.ok)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var controls: some View {
        RecordButton(isRecording: camera.isRecording) {
            if camera.isRecording {
                camera.stop()
            } else {
                camera.start { url in
                    camera.teardown()
                    onFinish(url)
                    dismiss()
                }
            }
        }
        // No gradient behind it. It was a black box the width of the button,
        // because once the guidance text above it went the column had nothing
        // left to make it full width.
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    // MARK: No camera

    private var unavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.7))

            Text(camera.isAuthorized
                 ? "No camera here"
                 : "Trace needs the camera")
                .font(Theme.serif(22, .semibold))
                .foregroundStyle(.white)

            Text(camera.isAuthorized
                 ? "This device has no camera Trace can use, which is always true of the Simulator. Import a clip you already filmed instead."
                 : "Recording needs permission to use the camera. You can allow it in Settings, or import a clip you already filmed.")
                .font(Theme.ui(14.5))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onFinish(nil)
                dismiss()
            } label: {
                Text("Back")
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 34)
    }
}
