import Foundation
import AVFoundation
import UIKit

/// The camera, for one photograph of a wall.
///
/// A separate object from `CameraController` because the two want different
/// things from the session: that one wants 60fps video and a movie file, this
/// one wants a single high resolution still. Sharing them would mean one object
/// reconfiguring itself for two jobs, which is where capture bugs live.
@MainActor
final class StillCamera: NSObject, ObservableObject {

    @Published var isAuthorized = false
    @Published var isAvailable = false
    @Published var isCapturing = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var completion: ((UIImage?) -> Void)?

    func prepare() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
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
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            isAvailable = false
            errorMessage = "No camera on this device. Choose a photo from your library instead."
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        isAvailable = true
        Task.detached { [session] in session.startRunning() }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        // Said out loud rather than returned quietly, for the same reason the
        // record button says it: a button that hits a guard and returns looks
        // exactly like a button that was never tapped.
        guard isAvailable else {
            errorMessage = "The camera is not ready yet. Give it a moment and tap again."
            return
        }
        guard !isCapturing else { return }
        self.completion = completion
        isCapturing = true
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func teardown() {
        let session = self.session
        Task.detached { if session.isRunning { session.stopRunning() } }
    }
}

extension StillCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            self.isCapturing = false
            if let error { self.errorMessage = error.localizedDescription }
            self.completion?(image)
            self.completion = nil
        }
    }
}
