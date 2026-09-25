import Foundation
import AVFoundation
import SwiftUI
import UIKit

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
    /// True while something else has the camera: a call, Control Center, the
    /// screen locking. The screen says so rather than going quiet.
    @Published var isInterrupted = false

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
        watchTheSession()
        configure()
    }

    /// What the session does when it is not being asked.
    ///
    /// A capture session is interrupted by things that have nothing to do with
    /// this app: a phone call, Control Center, the screen locking with the
    /// phone on the floor. Without this the app finds out only when the
    /// recording ends in an error, which is the worst moment and the least
    /// informative place to learn it.
    private func watchTheSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                           object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isInterrupted = true }
        }
        center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                           object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isInterrupted = false }
        }
        // Media services reset takes the session down with it. Starting it
        // again is the documented recovery, and without it the preview is a
        // black rectangle that never comes back.
        center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                           object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            Task { @MainActor in
                guard let self else { return }
                if error?.code == .mediaServicesWereReset {
                    let session = self.session
                    Task.detached { if !session.isRunning { session.startRunning() } }
                } else {
                    self.errorMessage = "The camera stopped. Tap record to try again."
                }
            }
        }
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

        // 60fps where the device offers it at full quality, and 1080p30 where
        // it does not. Jerk is a third derivative and deadpoint timing is
        // measured in tens of milliseconds, so frame rate matters; it does not
        // matter enough to film a gym through a worse sensor readout.
        //
        // The trap is binning. Most iPhones reach 60 and 120 by reading the
        // sensor at half resolution and combining pixels, and a binned format
        // is visibly noisier indoors, which is the only place this app is ever
        // used. Taking the last format that could manage 60 walked straight
        // into one: on a recent iPhone that is a 4K or 240fps slow motion
        // format, and those are binned.
        //
        // So: full readout only, 60fps, as close to 1080p as offered. If the
        // device has no such format, no override happens at all and the
        // session's own 1080p preset stands. Thirty good frames beat sixty
        // grainy ones.
        // The lock has to succeed before anything is set, and the unlock has to
        // be the one that matches it.
        //
        // `try?` and then unlocking regardless is a crash waiting for the one
        // moment the device is busy: setting the format without the lock, and
        // unlocking a lock never taken, both raise, and a raised exception here
        // closes the app on the screen it opened. When the lock cannot be had,
        // the session's own 1080p preset stands, which is what happens on every
        // phone with no unbinned sixty anyway.
        if let format = best60Format(on: device), (try? device.lockForConfiguration()) != nil {
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
        // The phone is on the floor and nobody is touching it, which is exactly
        // the state iOS locks the screen for. Locking interrupts the session,
        // and the recording of the climb you are in the middle of ends there.
        // This is the whole reason a capture screen turns auto lock off.
        UIApplication.shared.isIdleTimerDisabled = true
        Task.detached { [session] in session.startRunning() }
    }

    /// The best full-readout format that reaches 60fps, at or below 1080p.
    ///
    /// Nil when the device has none, which is the signal to leave the session's
    /// preset alone rather than to settle for a binned one.
    nonisolated static func best60(among formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        let candidates = formats.filter { f in
            let size = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard size.width <= 1920, size.height <= 1920 else { return false }
            guard !f.isVideoBinned else { return false }
            return f.videoSupportedFrameRateRanges.contains {
                $0.maxFrameRate >= 60 && $0.minFrameRate <= 60
            }
        }
        // Largest of them, which is 1080p wherever 1080p is offered unbinned.
        return candidates.max { a, b in
            let x = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let y = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(x.width) * Int(x.height) < Int(y.width) * Int(y.height)
        }
    }

    private func best60Format(on device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        Self.best60(among: device.formats)
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
        UIApplication.shared.isIdleTimerDisabled = false
        NotificationCenter.default.removeObserver(self)
        let session = self.session
        Task.detached { if session.isRunning { session.stopRunning() } }
    }
}

// MARK: - What an error at the end of a recording means

extension CameraController {

    /// What to do with a recording that ended in an error.
    ///
    /// Most of them are not what they look like. When a call arrives, or the
    /// screen locks, or Control Center comes down, iOS stops the recording and
    /// reports an error, but it has already finished writing a perfectly good
    /// file and says so in the error itself. Treating every error as a loss
    /// threw away the climb somebody had just done, and closed the screen while
    /// doing it.
    enum Ending: Equatable {
        /// Use the clip. Possibly cut short, but a climb.
        case keep(URL)
        /// Nothing usable was written, and this is why.
        case lost(String)
    }

    nonisolated static func ending(for url: URL, error: Error?) -> Ending {
        guard let error = error as NSError? else { return .keep(url) }
        // The key AVFoundation sets when it stopped the recording itself and
        // the file on disk is complete.
        if error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true {
            return .keep(url)
        }
        return .lost(error.localizedDescription)
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        let ending = Self.ending(for: outputFileURL, error: error)
        Task { @MainActor in
            self.isRecording = false
            switch ending {
            case .keep(let url):
                self.completion?(url)
            case .lost(let why):
                self.errorMessage = "\(why) Nothing was saved. Tap record to go again."
                self.completion?(nil)
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
