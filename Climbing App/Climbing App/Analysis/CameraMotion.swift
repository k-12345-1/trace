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

        /// Whether the phone was still enough to measure a climb against.
        var isStatic: Bool {
            confidence >= minimumConfidence && travel <= staticTravel
        }
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
    static let workingHeight = 240.0

    // MARK: Reading

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
        let interval = 1.0 / samplesPerSecond

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
                guard let last = previous else { return false }

                attempted += 1
                let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: buffer)
                let handler = VNImageRequestHandler(cvPixelBuffer: last)
                try? handler.perform([request])
                guard let alignment = request.results?.first as? VNImageTranslationAlignmentObservation
                else { return false }

                registered += 1
                let t = alignment.alignmentTransform
                let step = hypot(Double(t.tx), Double(t.ty)) / frameHeight
                travel += step
                net.x += t.tx
                net.y += t.ty
                return false
            }
            if stop { break }
        }

        guard attempted > 0 else { return nil }
        return Reading(travel: travel,
                       drift: hypot(Double(net.x), Double(net.y)) / frameHeight,
                       confidence: Double(registered) / Double(attempted))
    }
}
