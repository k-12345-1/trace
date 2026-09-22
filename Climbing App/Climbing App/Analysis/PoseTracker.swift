import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Runs Vision body-pose over a recorded clip.
///
/// Analysis happens after capture rather than live. Sustained 60fps capture plus
/// per-frame ML heats the phone badly, and nothing about the feedback needs to be
/// real time: you look at it between burns.
enum PoseTracker {

    enum TrackingError: LocalizedError {
        case noVideoTrack
        case readerFailed(String)
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "That file has no video in it."
            case .readerFailed(let m): return "Could not read the clip. \(m)"
            }
        }
    }

    /// Vision joint names mapped onto the joints we actually use.
    private static let mapping: [VNHumanBodyPoseObservation.JointName: JointID] = [
        .nose: .nose, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
        .root: .root
    ]

    /// Reads every frame of the clip and returns a pose time series.
    /// - Parameter progress: called on an arbitrary queue with 0...1.
    static func track(url: URL, progress: @escaping (Double) -> Void) async throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrackingError.noVideoTrack
        }

        let duration = try await asset.load(.duration).seconds
        let transform = try await track.load(.preferredTransform)
        let orientation = cgOrientation(for: transform)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw TrackingError.readerFailed("output rejected") }
        reader.add(output)
        guard reader.startReading() else {
            throw TrackingError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        var frames: [PoseFrame] = []
        let request = VNDetectHumanBodyPoseRequest()

        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds

            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
            try? handler.perform([request])

            // Crowded gyms put several people in frame. Take the largest, which
            // is reliably the climber when the phone is placed at the base of the wall.
            let observation = (request.results ?? [])
                .max(by: { boundingHeight($0) < boundingHeight($1) })

            if let observation {
                frames.append(makeFrame(from: observation, time: time))
            } else {
                frames.append(PoseFrame(time: time, joints: [:], com: nil, meanConfidence: 0))
            }

            if duration > 0 { progress(min(1, time / duration)) }
        }

        if reader.status == .failed {
            throw TrackingError.readerFailed(reader.error?.localizedDescription ?? "read failed")
        }
        return smooth(frames)
    }

    /// Body pose observations carry no bounding box, so the climber's apparent size
    /// is measured from the spread of their own tracked joints.
    private static func boundingHeight(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? o.recognizedPoints(.all) else { return 0 }
        let ys = points.values.filter { $0.confidence > 0.25 }.map { $0.location.y }
        guard let lo = ys.min(), let hi = ys.max() else { return 0 }
        return hi - lo
    }

    private static func makeFrame(from o: VNHumanBodyPoseObservation, time: Double) -> PoseFrame {
        var joints: [JointID: Joint] = [:]
        let points = (try? o.recognizedPoints(.all)) ?? [:]

        for (visionName, id) in mapping {
            guard let p = points[visionName], p.confidence > 0 else { continue }
            // Vision is normalised with origin bottom-left. Flip to top-left so the
            // overlay and the metrics share one coordinate system.
            joints[id] = Joint(x: Double(p.location.x),
                               y: Double(1 - p.location.y),
                               confidence: Double(p.confidence))
        }

        let usable = joints.values.filter { $0.isUsable }
        let mean = usable.isEmpty ? 0 : usable.map(\.confidence).reduce(0, +) / Double(usable.count)
        let com = CenterOfMass.estimate(joints: joints)

        return PoseFrame(time: time, joints: joints, com: com,
                         meanConfidence: usable.count >= 6 ? mean : 0)
    }

    /// A light 5-tap moving average on the COM. Vision jitters a few pixels frame to
    /// frame, and jerk is a third derivative, so raw noise would swamp the signal.
    static func smooth(_ frames: [PoseFrame]) -> [PoseFrame] {
        guard frames.count > 5 else { return frames }
        var out = frames
        let window = 2
        for i in frames.indices {
            var sx = 0.0, sy = 0.0, n = 0.0
            for k in max(0, i - window)...min(frames.count - 1, i + window) {
                guard let c = frames[k].com else { continue }
                sx += c.x; sy += c.y; n += 1
            }
            out[i].com = n > 0 ? CGPoint(x: sx / n, y: sy / n) : nil
        }
        return out
    }

    /// Phones record with the pixels in landscape and a rotation in the metadata.
    /// Vision needs that rotation or every angle we measure is wrong.
    private static func cgOrientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0):   return .right
        case (0, -1, 1, 0):   return .left
        case (-1, 0, 0, -1):  return .down
        default:              return .up
        }
    }
}
