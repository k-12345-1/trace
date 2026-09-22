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

            VStack {
                topBar
                Spacer()
                if camera.isAvailable { controls }
            }
        }
        .task { await camera.prepare() }
        .onDisappear { camera.teardown() }
    }

    // MARK: Framing guide

    private var framingGuide: some View {
        GeometryReader { geo in
            ZStack {
                // Rule of thirds, so the climber can be kept centred and whole.
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
                onFinish(nil)
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(Theme.mono(11, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
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
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if !camera.isRecording {
                Text("Side on if you can. Trace measures how far your hips sit from your feet, and that only works when it can see your profile.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }

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
            .padding(.bottom, 26)
        }
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: No camera

    private var unavailable: some View {
        VStack(spacing: 14) {
            MicroLabel(text: "No camera")
            Text(camera.isAuthorised
                 ? "This device has no camera Trace can use. Import a clip from your library instead."
                 : "Trace needs the camera to watch you climb. You can still import a clip you already filmed.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            FlatButton(title: "Back") {
                onFinish(nil)
                dismiss()
            }
            .frame(width: 200)
        }
        .padding(30)
    }
}
