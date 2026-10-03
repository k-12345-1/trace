import Testing
import Foundation
import AVFoundation
import CoreImage
@testable import ClimbingApp

private final class PanToken {}

/// A phone that follows the climber, built from the still fixture.
///
/// There is no handheld clip in the repository, so one is made: the still
/// clip seen through a window that slides up it, which is what a phone
/// tilting up to follow a climber films. The camera reading has to notice,
/// and the steadied skeleton has to put a point on the wall back where it
/// was. Body pose does not run in the simulator, so the climber here is a
/// point moved by the exact pan the clip was built with, which tests the
/// registration, the interpolation between samples and both signs.
@Suite("A followed climber", .serialized)
struct PanTests {
    static let out = FileManager.default.temporaryDirectory.appendingPathComponent("trace-panned.mp4")
    /// The window is this share of the source height.
    static let window = 0.7
    /// The window starts this far down and rises to the top by the end.
    static let startDrop = 0.28

    @Test("A followed climber is put back on the wall")
    func followedClimberIsPutBack() async throws {
        let bundle = Bundle(for: PanToken.self)
        let src = try #require(bundle.url(forResource: "climber", withExtension: "mp4"))
        let (h, duration) = try await Self.writePanned(from: src, to: Self.out)

        let reading = try #require(await CameraMotion.read(url: Self.out))
        print("PAN reading travel \(reading.travel) drift \(reading.drift) conf \(reading.confidence) samples \(reading.path.count)")
        #expect(!reading.isStatic)
        #expect(abs(reading.travel - Self.startDrop / Self.window) < 0.03)

        // Body pose does not run in the simulator, so the climber is a
        // point that stays put on the wall while the window slides up it.
        func drop(_ t: Double) -> Double { Self.startDrop * (1 - min(t / duration, 1)) }
        let wallY = 0.6, wallX = 0.5
        var panned: [PoseFrame] = []
        var t = 0.0
        while t < duration {
            let y = (wallY - drop(t)) / Self.window
            var f = PoseFrame(time: t, joints: [:], com: CGPoint(x: wallX, y: y), meanConfidence: 1)
            f.joints[.root] = Joint(x: wallX, y: y, confidence: 1)
            panned.append(f)
            t += 1.0 / 30
        }
        let steadied = CameraMotion.stabilized(panned, by: reading)
        let t0 = reading.path.first?.time ?? 0
        let expected = (wallY - drop(t0)) / Self.window
        let raw = panned.map { Double(abs(($0.com?.y ?? 0) - expected)) }
        let fixed = steadied.map { Double(abs(($0.com?.y ?? 0) - expected)) }
        let sideways = steadied.map { Double(abs(($0.com?.x ?? 0) - wallX)) }
        let med = { (a: [Double]) -> Double in let s = a.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }
        print("PAN frames \(fixed.count) median error raw \(med(raw)) steadied \(med(fixed)) max steadied \(fixed.max() ?? .nan) max sideways \(sideways.max() ?? .nan) h \(h)")
        #expect(med(fixed) < 0.01)
        #expect((fixed.max() ?? 1) < 0.03)
        #expect((sideways.max() ?? 1) < 0.01)
    }

    /// Writes the panned clip; returns the source height and duration.
    static func writePanned(from src: URL, to dst: URL) async throws -> (Double, Double) {
        try? FileManager.default.removeItem(at: dst)
        let asset = AVURLAsset(url: src)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        let w = Int(size.width), h = Int(size.height), wh = Int(Double(h) * window) / 2 * 2
        let writer = try AVAssetWriter(outputURL: dst, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: wh])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: wh])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        #expect(reader.startReading())
        let ci = CIContext()
        while let sample = output.copyNextSampleBuffer() {
            guard let buf = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample)
            let drop = startDrop * (1 - min(t.seconds / duration, 1))
            // Top-left origin: the window's top edge sits `drop` of the
            // height down. Core Image counts from the bottom.
            let top = Double(h) * drop
            let rect = CGRect(x: 0, y: Double(h) - top - Double(wh), width: Double(w), height: Double(wh)).integral
            let image = CIImage(cvPixelBuffer: buf).cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &made)
            guard let dstBuf = made else { continue }
            ci.render(image, to: dstBuf)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            adaptor.append(dstBuf, withPresentationTime: t)
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
        return (Double(h), duration)
    }
}
