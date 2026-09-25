import Foundation
import AVFoundation
import SwiftUI

/// Capture is deliberately constrained: phone on the floor, square to the wall,
/// whole boulder in frame. Every posture metric depends on a known viewing angle,
/// so guiding the setup is what makes the numbers downstream trustworthy.
@MainActor
final class CameraController: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var isAuthorized = false
    @Published var isAvailable = false
    @Published var elapsed: Double = 0
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private var completion: ((URL?) -> Void)?

    func prepare() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: isAuthorized = true
        case .notDetermined: isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default: isAuthorized = false
        }
        guard isAuthorized else { return }
        configure()
    }

    private func configure() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            isAvailable = false
            errorMessage = "No camera on this device. Import a clip instead."
            return
        }
        session.addInput(input)

        // 60fps where the device offers it. Jerk is a third derivative and
        // deadpoint timing is measured in tens of milliseconds, so frame rate matters.
        //
        // Capped at 1080p and at 60, rather than simply taking the last format
        // that can reach 60. The list runs low to high, so the last match on a
        // recent iPhone is 4K or a 240fps slow motion format: far more data than
        // pose tracking can use, and a slow motion format is not a format this
        // output records the way you would expect.
        if let format = device.formats.last(where: { f in
            let size = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard size.width <= 1920, size.height <= 1920 else { return false }
            return f.videoSupportedFrameRateRanges.contains {
                $0.maxFrameRate >= 60 && $0.minFrameRate <= 60
            }
        }) {
            try? device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            device.unlockForConfiguration()
        }

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            isAvailable = false
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        isAvailable = true
        Task.detached { [session] in session.startRunning() }
    }

    func start(completion: @escaping (URL?) -> Void) {
        // Said out loud rather than returned quietly. A button whose action runs
        // and then hits a guard is indistinguishable, on the screen, from a
        // button that was never tapped, and that ambiguity cost a long time.
        guard isAvailable else {
            errorMessage = "The camera is not ready yet. Give it a moment and tap again."
            return
        }
        guard !output.isRecording else { return }
        guard output.connection(with: .video) != nil else {
            errorMessage = "This camera cannot record video. Import a clip instead."
            return
        }
        self.completion = completion
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")
        output.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 0.1 }
        }
    }

    func stop() {
        guard output.isRecording else { return }
        output.stopRecording()
        timer?.invalidate()
        timer = nil
    }

    func teardown() {
        timer?.invalidate()
        let session = self.session
        Task.detached { if session.isRunning { session.stopRunning() } }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            if let error {
                self.errorMessage = error.localizedDescription
                self.completion?(nil)
            } else {
                self.completion?(outputFileURL)
            }
            self.completion = nil
        }
    }
}

// MARK: - Preview layer

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // It shows the camera and does nothing else. A UIView is interactive by
        // default, and this one is full screen inside a presented cover, which
        // is enough for it to take the taps meant for the controls drawn over
        // it: on the device both Cancel and the record button were dead while
        // the screen looked perfectly normal.
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
