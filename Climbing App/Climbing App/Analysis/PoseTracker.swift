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

    /// A compact identity signature for choosing the same person from frame to frame.
    ///
    /// Vision gives us an observation, not a persistent person ID. Picking the
    /// largest observation independently on every frame is surprisingly easy to
    /// fool in a gym: a bystander can step closer to the camera for one frame and
    /// steal the whole skeleton. The signature makes the tracker prefer the body
    /// that continues the previous trajectory, and only reacquire a new person
    /// after a short genuine loss.
    private struct ObservationSignature {
        let center: CGPoint
        let width: Double
        let height: Double
        let confidence: Double
    }

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
        var previousObservation: ObservationSignature?
        var lostFrames = 0
        var lastReported = -1.0

        while let sample = output.copyNextSampleBuffer() {
            // One pool per frame.
            //
            // This loop is synchronous and holds a 1080p buffer every time
            // round, so anything autoreleased inside it would have nothing
            // draining it until the whole clip had been read. Measured, it does
            // not: four hundred frames move the footprint by nothing, which is
            // what the memory test asserts. The pool is what keeps that true
            // when somebody adds a line to this loop, not a fix for a leak that
            // was there.
            autoreleasepool {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds

                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
                try? handler.perform([request])

                // Crowded gyms put several people in frame. The largest body is a
                // good first guess, but once the climb starts, temporal continuity
                // is much safer than size alone. This prevents a nearby bystander
                // from becoming the climber for a few frames.
                let observation = selectObservation(from: request.results ?? [],
                                                     previous: previousObservation,
                                                     lostFrames: lostFrames)

                if let observation {
                    previousObservation = signature(of: observation)
                    lostFrames = 0
                    frames.append(makeFrame(from: observation, time: time))
                } else {
                    lostFrames += 1
                    frames.append(PoseFrame(time: time, joints: [:], com: nil, meanConfidence: 0))
                }

                // Reported in fiftieths, not per frame. Every call to this hops
                // to the main actor to move a progress bar; at sixty a second
                // that is a queue of work the main thread cannot clear, on top
                // of the tracking itself, and the screen that is meant to show
                // progress stops responding instead.
                guard duration > 0 else { return }
                let done = min(1, time / duration)
                if done - lastReported >= 0.02 || done >= 1 {
                    lastReported = done
                    progress(done)
                }
            }
        }

        if reader.status == .failed {
            throw TrackingError.readerFailed(reader.error?.localizedDescription ?? "read failed")
        }
        let gated = rejectingImpossibleMoves(frames)
        return smooth(stabilizeIsolatedJoints(gated))
    }

    /// Body pose observations carry no bounding box, so the climber's apparent size
    /// is measured from the spread of their own tracked joints.
    private static func signature(of o: VNHumanBodyPoseObservation) -> ObservationSignature? {
        guard let points = try? o.recognizedPoints(.all) else { return nil }
        let usable = points.values.filter { $0.confidence > 0.25 }
        guard usable.count >= 6 else { return nil }
        let xs = usable.map { Double($0.location.x) }
        let ys = usable.map { Double($0.location.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return ObservationSignature(
            center: CGPoint(x: (minX + maxX) / 2, y: 1 - (minY + maxY) / 2),
            width: maxX - minX,
            height: maxY - minY,
            confidence: usable.map { Double($0.confidence) }.reduce(0, +) / Double(usable.count)
        )
    }

    private static func selectObservation(
        from observations: [VNHumanBodyPoseObservation],
        previous: ObservationSignature?,
        lostFrames: Int
    ) -> VNHumanBodyPoseObservation? {
        let candidates = observations.compactMap { o -> (VNHumanBodyPoseObservation, ObservationSignature)? in
            guard let s = signature(of: o) else { return nil }
            return (o, s)
        }

        guard !candidates.isEmpty else { return nil }
        guard let previous else {
            return candidates.max {
                let a = $0.1.height * $0.1.confidence
                let b = $1.1.height * $1.1.confidence
                return a < b
            }?.0
        }

        let prevH = max(previous.height, 0.05)
        let scored = candidates.map { item -> (VNHumanBodyPoseObservation, Double) in
            let s = item.1
            let centerDistance = hypot(Double(s.center.x - previous.center.x),
                                       Double(s.center.y - previous.center.y)) / prevH
            let scaleRatio = max(s.height, 0.001) / prevH
            let logScale = abs(log(scaleRatio))
            // Center continuity dominates. Size continuity is a secondary cue:
            // the same climber can change apparent height as they crouch.
            let continuity = centerDistance + logScale * 0.45
            let confidenceBonus = (1 - item.1.confidence) * 0.15
            return (item.0, continuity + confidenceBonus)
        }

        let best = scored.min { $0.1 < $1.1 }
        // A fixed camera should not teleport the tracked body by more than about
        // one body height in one frame. During a short occlusion, let the tracker
        // reacquire after a few frames rather than silently switching identities.
        if let best, best.1 <= 1.15 || lostFrames >= 6 {
            return best.0
        }
        return nil
    }

    private static func boundingHeight(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        CGFloat(signature(of: o)?.height ?? 0)
    }

    private static func makeFrame(from o: VNHumanBodyPoseObservation, time: Double) -> PoseFrame {
        var joints: [JointID: Joint] = [:]
        let points = (try? o.recognizedPoints(.all)) ?? [:]

        for (visionName, id) in mapping {
            guard let p = points[visionName], p.confidence > 0 else { continue }
            // Vision is normalized with origin bottom-left. Flip to top-left so the
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

    /// How much of a second the moving average covers, either side.
    ///
    /// A duration, not a number of frames, and that is the whole point of it.
    /// Vision jitters a few pixels frame to frame and jerk is a third
    /// derivative, so the centre of mass has to be filtered before anything is
    /// derived from it. A five tap window does that over sixty six
    /// milliseconds at thirty frames a second and over thirty three at sixty:
    /// the same climb, filmed on the same phone, came out measurably jerkier at
    /// the higher frame rate, because half as much of the jitter had been taken
    /// out before the third derivative amplified what was left.
    ///
    /// That matters here more than it would elsewhere. Trace films at sixty
    /// where the camera offers an unbinned format and thirty where it does not,
    /// and an imported clip is whatever the climber's phone recorded, so one
    /// library holds both. Smoothness is only ever compared against the
    /// climber's own earlier climbs, which is exactly the comparison this
    /// silently broke.
    static let smoothingSeconds = 0.066

    /// A moving average on the COM over a fixed slice of time.
    /// A limb cannot move faster than this, in torso lengths per second.
    ///
    /// A torso is roughly half a metre, so this is about ten metres a second at
    /// the wrist: far beyond a thrown hand, which peaks near seven torso lengths
    /// a second on real footage, and far below the nonsense. Anything above it
    /// is the tracker having put a joint somewhere it is not.
    static let impossibleSpeed = 20.0

    /// Throws away joint samples that arrived impossibly fast.
    ///
    /// `smooth` averages the centre of mass and has never touched the
    /// individual joints, so every angle, every foot placement and every reach
    /// has been computed on raw output. On real footage that output contains
    /// occasional gross errors: on the fixture clip an ankle moves 4.56 torso
    /// lengths inside one sixtieth of a second, which is two metres, and the
    ///97th percentile frame-to-frame ankle speed is 27 torso lengths a second.
    ///
    /// These are not jitter and a filter does not fix them. A median over five
    /// frames leaves the 97th percentile at 16, because the joint does not
    /// flicker for one frame, it jumps somewhere wrong and stays for several.
    /// Nor is it left and right being confused, which accounts for 1.5% of
    /// ankle frames and no more. It is simply a wrong answer, and the honest
    /// thing to do with a wrong answer is drop it: confidence goes to zero, and
    /// every reader in the app already knows how to skip a joint it cannot see.
    ///
    /// Measured on the fixture: 3.5% of ankle samples go, the worst frame-to-
    /// frame speed falls from 138 to 20, and the reach reading is unchanged.
    static func rejectingImpossibleMoves(_ frames: [PoseFrame]) -> [PoseFrame] {
        guard let torso = MetricsEngine.medianTorso(frames), torso > 0.01 else { return frames }
        var out = frames

        for id in JointID.allCases {
            // The last sample believed, which a rejected one never becomes:
            // otherwise one bad frame drags the reference with it and the good
            // frame that follows looks like the impossible move.
            var believed: (time: Double, point: CGPoint)?
            for i in frames.indices {
                guard let p = frames[i].pt(id) else { continue }
                if let last = believed {
                    let dt = max(frames[i].time - last.time, 0.0005)
                    let speed = hypot(Double(p.x - last.point.x),
                                      Double(p.y - last.point.y)) / dt / torso
                    if speed > impossibleSpeed {
                        out[i].joints[id]?.confidence = 0
                        continue
                    }
                }
                believed = (frames[i].time, p)
            }
        }
        return out
    }

    /// Removes an isolated joint spike without blurring genuine movement.
    ///
    /// A median filter over the whole climb would flatten deadpoints and fast
    /// foot moves. Instead this only repairs the specific shape of a one-frame
    /// excursion: the point jumps away from both neighbours and then returns.
    static func stabilizeIsolatedJoints(_ frames: [PoseFrame]) -> [PoseFrame] {
        guard frames.count >= 3 else { return frames }
        var out = frames

        for i in 1..<(frames.count - 1) {
            for id in JointID.allCases {
                guard let a = frames[i - 1].pt(id),
                      let b = frames[i].pt(id),
                      let c = frames[i + 1].pt(id) else { continue }

                let ab = hypot(Double(a.x - b.x), Double(a.y - b.y))
                let bc = hypot(Double(b.x - c.x), Double(b.y - c.y))
                let ac = hypot(Double(a.x - c.x), Double(a.y - c.y))

                // A real fast move can be large, but it usually continues in
                // roughly the same direction. An isolated tracker spike goes
                // out and comes back, so the two legs are much longer than the
                // direct neighbour-to-neighbour distance.
                guard ab > 0.018, bc > 0.018,
                      ab + bc > max(ac * 2.4, 0.05) else { continue }

                let confidence = min(frames[i - 1].joints[id]?.confidence ?? 0,
                                     frames[i + 1].joints[id]?.confidence ?? 0)
                guard confidence >= 0.45 else { continue }

                out[i].joints[id] = Joint(
                    x: Double((a.x + c.x) / 2),
                    y: Double((a.y + c.y) / 2),
                    confidence: confidence
                )
            }
            out[i].com = CenterOfMass.estimate(joints: out[i].joints)
            let usable = out[i].joints.values.filter { $0.isUsable }
            out[i].meanConfidence = usable.count >= 6
                ? usable.map(\.confidence).reduce(0, +) / Double(usable.count)
                : 0
        }
        return out
    }

    static func smooth(_ frames: [PoseFrame]) -> [PoseFrame] {
        guard frames.count > 5 else { return frames }
        var out = frames

        // From the clip's own timestamps rather than from an assumed rate.
        var gaps: [Double] = []
        for (a, b) in zip(frames, frames.dropFirst()) where b.time > a.time {
            gaps.append(b.time - a.time)
        }
        let step = gaps.isEmpty ? 1.0 / 30.0 : gaps.sorted()[gaps.count / 2]
        let window = max(1, Int((smoothingSeconds / max(step, 1e-6)).rounded()))

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
