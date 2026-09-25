import Testing
import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
@testable import ClimbingApp

/// Tracking a clip has to leave the memory it borrowed.
///
/// This is here because of the worst kind of bug: the app closing, with no
/// crash, part way through analyzing a climb that had just been recorded. iOS
/// does not report a memory kill as a crash, so there is nothing to read
/// afterwards and nothing on screen before it. The only way to see it is to
/// measure the footprint across a clip and watch it climb.
///
/// The loop in `PoseTracker.track` is synchronous and hands every frame to
/// Vision, which autoreleases a working copy of it. Without a pool per frame
/// none of those are freed until the whole clip has been read, so the footprint
/// rises with the length of the clip rather than staying flat, and a long climb
/// filmed at sixty is enough to be killed for it.
@Suite("Tracking memory")
struct TrackingMemoryTests {

    /// Resident footprint in megabytes, as iOS itself accounts for it when
    /// deciding what to kill.
    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_000_000
    }

    /// A real 1080p clip, written the way the camera writes one, with something
    /// moving in it so Vision has work to do on every frame.
    private func clip(frames count: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080, AVVideoHeightKey: 1920
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 1080,
                kCVPixelBufferHeightKey as String: 1920
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for i in 0..<count {
            autoreleasepool {
                guard let pool = adaptor.pixelBufferPool else { return }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { return }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer),
                   let context = CGContext(
                    data: base, width: 1080, height: 1920, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                    context.setFillColor(gray: 0.15, alpha: 1)
                    context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
                    context.setFillColor(gray: 0.85, alpha: 1)
                    let y = 200 + CGFloat(i) * 4
                    context.fill(CGRect(x: 380, y: y, width: 320, height: 700))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                while !input.isReadyForMoreMediaData { usleep(2000) }
                adaptor.append(buffer, withPresentationTime:
                                CMTime(value: CMTimeValue(i), timescale: 60))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// The headline. A clip twice as long must not cost twice the memory.
    ///
    /// The bound is generous on purpose: Vision loads its model on first use and
    /// the frames themselves are kept, both of which are real and bounded. What
    /// this catches is the unbounded case, which on this clip was hundreds of
    /// megabytes and on a real climb was the app.
    @Test("Tracking a clip does not grow the footprint with its length")
    func trackingHoldsItsMemory() async throws {
        let url = try await clip(frames: 400)
        defer { try? FileManager.default.removeItem(at: url) }

        // Once through first, so the model load and the one-off allocations are
        // behind us and what is measured second is the loop itself.
        _ = try await PoseTracker.track(url: url) { _ in }

        let before = footprintMB()
        let frames = try await PoseTracker.track(url: url) { _ in }
        let after = footprintMB()

        print("FOOTPRINT before \(Int(before))MB after \(Int(after))MB delta \(Int(after - before))MB frames \(frames.count)")
        #expect(frames.count > 100, "only \(frames.count) frames were read")
        #expect(after - before < 120,
                "tracking grew the footprint by \(Int(after - before))MB")
    }

    /// Progress is reported in steps, not per frame. Every call hops to the main
    /// actor to move a bar, and sixty a second is a queue the main thread cannot
    /// clear while it is also drawing the screen that shows it.
    @Test("Progress is reported in steps, not per frame")
    func progressIsThrottled() async throws {
        let url = try await clip(frames: 150)
        defer { try? FileManager.default.removeItem(at: url) }

        let counter = Counter()
        _ = try await PoseTracker.track(url: url) { _ in counter.bump() }
        #expect(counter.count <= 60, "progress was reported \(counter.count) times")
        #expect(counter.count >= 2, "progress was reported \(counter.count) times")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func bump() { lock.withLock { value += 1 } }
    }
}
