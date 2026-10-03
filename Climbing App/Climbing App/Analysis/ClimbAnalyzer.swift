import Foundation
import AVFoundation
import SwiftUI

/// Drives the whole pipeline for one clip: track, measure, find, store.
@MainActor
final class ClimbAnalyzer: ObservableObject {
    enum State {
        case idle
        case working(Double)
        case done(Climb)
        case failed(String)
    }

    @Published var state: State = .idle

    func analyze(sourceURL: URL, label: String, gymID: UUID? = nil,
                 grade: String = "", note: String = "") async {
        state = .working(0)
        do {
            let filename = try Store.shared.importVideo(from: sourceURL)
            let stored = Store.videosDirectory.appendingPathComponent(filename)

            let frames = try await PoseTracker.track(url: stored) { p in
                Task { @MainActor in self.state = .working(p) }
            }

            // Whether the phone stayed put, which decides whether anything
            // measured from where the body went in the frame is about the body.
            // A failure here is not a failure of the climb: nil means unknown,
            // and unknown is shown as such rather than as "still".
            let camera = try? await CameraMotion.read(url: stored)

            // When the phone moved, the measuring is done on the skeleton
            // with the phone's movement taken back out, so a climber the
            // operator followed up the wall is measured against the wall and
            // not against the frame. The stored frames stay as filmed: they
            // are drawn over the footage, and the footage still moves. A
            // still phone is left alone, because on a still phone the only
            // thing that can drag the registration is the climber.
            let measured = camera.map { $0.isStatic ? frames : CameraMotion.stabilized(frames, by: $0) }
                ?? frames

            // Findings read the ascent, for the same reason the metrics do: the
            // descent is not climbing, and counting it produces stops you did
            // not take and a wandering line you did not wander.
            let climbing = MetricsEngine.ascent(measured)
            let metrics = MetricsEngine.compute(frames: measured)
            // Smoothness is judged against this climber's own earlier tracked
            // attempts, so the history has to come in with the frames.
            // Only the attempts measured the same way. A history that mixes
            // whole-climb jerk with per-move jerk is not a history.
            let priorJerk = Store.shared.climbs
                .filter { $0.metrics.isTrustworthy }
                .compactMap { $0.metrics.movingJerk }
            let findings = FindingEngine.findings(from: metrics, frames: climbing,
                                                  priorJerk: priorJerk)

            // Topping out marks the send, so the person does not have to tell
            // the app something it just watched them do. It is only ever a
            // reading of where the body went, never a claim about the route,
            // and Mark unsent takes it back.
            let outcome = OutcomeEngine.outcome(frames: measured)
            let topped: Bool? = {
                switch outcome {
                case .topped: return true
                case .fell:   return false
                case .unclear: return nil   // leave it to the climber
                }
            }()

            let climb = Climb(
                recordedAt: Date(),
                videoFilename: filename,
                label: label,
                grade: grade.trimmingCharacters(in: .whitespaces),
                metrics: metrics,
                findings: findings,
                frames: frames,
                sent: topped,
                gymID: gymID,
                notes: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : ClimbNotes(note: note.trimmingCharacters(in: .whitespacesAndNewlines)),
                cameraTravel: camera?.travel
            )
            Store.shared.save(climb)
            state = .done(climb)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Video aspect ratio, needed so the overlay letterboxes exactly like the player.
enum VideoInfo {
    static func aspect(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return 9.0 / 16.0 }
        let displayed = size.applying(transform)
        let w = abs(displayed.width), h = abs(displayed.height)
        guard w > 0, h > 0 else { return 9.0 / 16.0 }
        return w / h
    }
}
