import Foundation
import CoreGraphics
import CoreVideo
import Vision

/// The people in a photograph of a wall, so the scanner can look past them.
///
/// A climber standing in the shot is a tan route with eight holds: shirt,
/// shorts, two arms, two legs. Vision can draw round a person; the pixels
/// inside are then neither wall nor route, and no colour is read from
/// them. Nil when Vision cannot run, which in the simulator it cannot, and
/// the scan reads the wall as before.
enum PeopleEngine {
    /// Where the people are, as a mask the size of a bitmap, or nil.
    static func mask(in image: CGImage, width: Int, height: Int) -> [Bool]? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first else { return nil }
        return resample(result.pixelBuffer, width: width, height: height)
    }

    /// A Vision mask, nearest-neighbour resampled to the bitmap's size.
    /// Vision's confidence is 0 to 255; half and over is a person.
    static func resample(_ pb: CVPixelBuffer, width: Int, height: Int) -> [Bool]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let mw = CVPixelBufferGetWidth(pb), mh = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        guard mw > 0, mh > 0, let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var out = [Bool](repeating: false, count: width * height)
        var any = false
        for y in 0..<height {
            let my = min(mh - 1, y * mh / max(height, 1))
            for x in 0..<width {
                let mx = min(mw - 1, x * mw / max(width, 1))
                if bytes[my * bpr + mx] >= 128 { out[y * width + x] = true; any = true }
            }
        }
        return any ? out : nil
    }
}
