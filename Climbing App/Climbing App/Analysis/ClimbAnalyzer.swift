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

    func analyze(sourceURL: URL, label: String, gymID: UUID? = nil) async {
        state = .working(0)
        do {
            let filename = try Store.shared.importVideo(from: sourceURL)
            let stored = Store.videosDirectory.appendingPathComponent(filename)

            let frames = try await PoseTracker.track(url: stored) { p in
                Task { @MainActor in self.state = .working(p) }
            }

            let metrics = MetricsEngine.compute(frames: frames)
            // Smoothness is judged against this climber's own earlier tracked
            // attempts, so the history has to come in with the frames.
            let priorJerk = Store.shared.climbs
                .filter { $0.metrics.isTrustworthy }
                .map(\.metrics.logJerk)
            let findings = FindingEngine.findings(from: metrics, frames: frames,
                                                  priorJerk: priorJerk)

            // Topping out marks the send, so the person does not have to tell
            // the app something it just watched them do. It is only ever a
            // reading of where the body went, never a claim about the route,
            // and Mark unsent takes it back.
            let outcome = OutcomeEngine.outcome(frames: frames)
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
                metrics: metrics,
                findings: findings,
                frames: frames,
                sent: topped,
                gymID: gymID
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
