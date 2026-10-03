import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Whether the phone stayed put.
///
/// ## Why this exists
///
/// Every spatial measurement in Trace is computed from the centre of mass in
/// image coordinates: re-lifting, round trips, the path ratio, the travel
/// between moves, entropy. All of them assume the frame is a fixed window onto
/// the wall, which is what the Record screen asks for: phone on the floor,
/// square to the wall, whole boulder in frame. Nothing checked it.
///
/// Point a friend's phone at a climber and they will follow them up the wall,
/// because that is what filming a person looks like. The climber then stays in
/// the middle of the frame for the whole climb, and their centre of mass, in
/// image coordinates, barely moves. What it does instead is bob, as the
/// operator over- and under-corrects. Trace read that bobbing as a climber
/// losing height and regaining it.
///
/// Measured on four real clips: one filmed from the floor moved the climber
/// 5.44 torso lengths up the frame over the climb. Three filmed by somebody
/// holding the phone moved them 1.42, 0.87 and 1.29. The second of those is a
/// climber who went up an entire wall, and Trace graded her "very inefficient,
/// 82% wasted", of which 78 points were "your height was gained twice".
///
/// ## What is measured
///
/// Frame-to-frame translation of the whole picture, from Vision's own image
/// registration. On a still phone consecutive frames line up and the
/// translation is a pixel of sensor noise. On a moving phone it is not.
///
/// Registration is dominated by whatever fills most of the frame, which on a
/// climbing clip is the wall, so this reads the background rather than the
/// climber. That is exactly what is wanted and also the one case it gets wrong:
/// a climber filling the frame on a featureless panel can drag the estimate.
/// `confidence` says how much of the clip registered at all.
enum CameraMotion {

    struct Reading {
        /// Total distance the picture travelled, summed frame to frame, as a
        /// fraction of the frame's height. Sums magnitudes, so a pan out and
        /// back counts twice rather than cancelling.
        let travel: Double
        /// Where the picture ended up against where it started, same units.
        /// A pan that follows a climber up a wall is mostly drift; a wobble is
        /// travel with little drift.
        let drift: Double
        /// The share of sampled pairs Vision could register.
        let confidence: Double
        /// Where the picture had got to at each sample, as a fraction of the
        /// frame, so a skeleton can be put back where the wall is.
        var path: [Offset] = []

        init(travel: Double, drift: Double, confidence: Double, path: [Offset] = []) {
            self.travel = travel
            self.drift = drift
            self.confidence = confidence
            self.path = path
        }

        /// Whether the phone was still enough to measure a climb against.
        var isStatic: Bool {
            confidence >= minimumConfidence && travel <= staticTravel
        }
    }

    /// Where the picture had moved to by a moment, in fractions of the frame
    /// width and height, top-left origin like the joints.
    struct Offset {
        let time: Double
        let dx: Double
        let dy: Double
    }

    // MARK: The judgements

    /// How far the picture may travel over the whole clip and still count as a
    /// still camera, in frame heights.
    ///
    /// A phone on the floor is not perfectly still: it gets nudged, and the
    /// registration itself has a noise floor. Measured, the clip filmed from
    /// the floor travelled 0.01 frame heights over thirty seconds, and the
    /// three handheld ones travelled 1.74, 1.87 and 2.96. Two orders of
    /// magnitude apart, with every pair registering, so this sits far clear of
    /// both rather than splitting a difference.
    static let staticTravel = 0.35
    /// Below this share of registered pairs the reading says nothing.
    static let minimumConfidence = 0.5

    /// How often to sample. Camera motion is slow compared to a climber, and
    /// registering every frame of a 60fps clip costs the same again as tracking
    /// it for a measurement that does not change between frames.
    static let samplesPerSecond = 6.0
    /// Registration runs on the picture at this height, which is plenty for a
    /// translation and a great deal cheaper than doing it at 1080p.
    ///
    /// Raised from 240 once the reading was used to steady the skeleton as
    /// well as to judge the phone: a pixel of registration noise at 240 is
    /// 0.4 percent of the frame per sample, which against a torso a fifth of
    /// the frame tall is most of the speed that counts as standing still.
    static let workingHeight = 540.0

    // MARK: Reading

    /// How far the picture moved between two frames, in pixels of the buffers,
    /// rows counted downward like the joints.
    ///
    /// Vision answers with the transform that lays the new frame over the old
    /// one, which is the opposite of where the picture went, and it counts
    /// rows upward where the joints count them downward. Both signs are
    /// settled against a synthetic shift in the tests, not the documentation.
    static func shift(from last: CVPixelBuffer, to buffer: CVPixelBuffer) -> CGPoint? {
        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: buffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: last)
        try? handler.perform([request])
        guard let alignment = request.results?.first as? VNImageTranslationAlignmentObservation
        else { return nil }
        let t = alignment.alignmentTransform
        return CGPoint(x: -t.tx, y: t.ty)
    }

    /// The frames with the phone's movement taken back out, so what is left
    /// is the climber against the wall.
    ///
    /// The picture's position is known at the sampled moments and read
    /// between them by a straight line, which over a sixth of a second is
    /// what a hand holding a phone does. The frames are left alone when the
    /// reading has no path, which is what an older climb has.
    static func stabilized(_ frames: [PoseFrame], by reading: Reading) -> [PoseFrame] {
        let path = reading.path
        guard path.count >= 2 else { return frames }
        var k = 0
        return frames.map { frame in
            while k + 1 < path.count - 1, path[k + 1].time <= frame.time { k += 1 }
            let a = path[k], b = path[k + 1]
            let span = max(b.time - a.time, 1e-6)
            let u = min(max((frame.time - a.time) / span, 0), 1)
            let dx = a.dx + (b.dx - a.dx) * u
            let dy = a.dy + (b.dy - a.dy) * u
            var out = frame
            for (id, j) in frame.joints {
                out.joints[id] = Joint(x: j.x - dx, y: j.y - dy, confidence: j.confidence)
            }
            if let c = frame.com { out.com = CGPoint(x: c.x - dx, y: c.y - dy) }
            return out
        }
    }

    static func read(url: URL) async throws -> Reading? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let size = try await track.load(.naturalSize)
        guard size.height > 0 else { return nil }

        let reader = try AVAssetReader(asset: asset)
        let scale = min(1, workingHeight / Double(size.height))
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(Double(size.width) * scale),
                kCVPixelBufferHeightKey as String: Int(Double(size.height) * scale)
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        // Measured against the working height, so the answer is in frame
        // heights whatever the clip's resolution.
        let frameHeight = Double(size.height) * scale
        let frameWidth = Double(size.width) * scale
        let interval = 1.0 / samplesPerSecond
        var path: [Offset] = []

        var previous: CVPixelBuffer?
        var lastSampled = -Double.infinity
        var travel = 0.0
        var net = CGPoint.zero
        var attempted = 0, registered = 0

        while let sample = output.copyNextSampleBuffer() {
            let stop = autoreleasepool { () -> Bool in
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return false }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard time - lastSampled >= interval else { return false }
                lastSampled = time

                defer { previous = buffer }
                guard let last = previous else {
                    path.append(Offset(time: time, dx: 0, dy: 0))
                    return false
                }

                attempted += 1
                guard let moved = shift(from: last, to: buffer) else { return false }

                registered += 1
                let step = hypot(Double(moved.x), Double(moved.y)) / frameHeight
                travel += step
                net.x += moved.x
                net.y += moved.y
                path.append(Offset(time: time,
                                   dx: Double(net.x) / frameWidth,
                                   dy: Double(net.y) / frameHeight))
                return false
            }
            if stop { break }
        }

        guard attempted > 0 else { return nil }
        return Reading(travel: travel,
                       drift: hypot(Double(net.x), Double(net.y)) / frameHeight,
                       confidence: Double(registered) / Double(attempted),
                       path: path)
    }
}
