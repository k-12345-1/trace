import Testing
import UIKit
import CoreVideo
@testable import ClimbingApp

/// A person in the shot is not a route.
@Suite("People in the shot")
struct PeopleTests {
    private func canvas(_ draw: (CGContext) -> Void) -> CGImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240), format: f).image { ctx in
            UIColor(white: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
            draw(ctx.cgContext)
        }.cgImage!
    }

    /// Three tan blobs make a tan route; masked out, they make nothing.
    @Test func maskedPixelsAreNotARoute() throws {
        let tan = UIColor(red: 0.70, green: 0.53, blue: 0.38, alpha: 1)
        let image = canvas { c in
            c.setFillColor(tan.cgColor)
            c.fillEllipse(in: CGRect(x: 100, y: 60, width: 40, height: 40))
            c.fillEllipse(in: CGRect(x: 90, y: 120, width: 24, height: 60))
            c.fillEllipse(in: CGRect(x: 126, y: 120, width: 24, height: 60))
            c.setFillColor(UIColor.red.cgColor)
            for y in [30, 100, 170] { c.fillEllipse(in: CGRect(x: 30, y: y, width: 24, height: 20)) }
        }
        let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.paletteWidth))
        var mask = [Bool](repeating: false, count: bmp.width * bmp.height)
        for y in 0..<bmp.height { for x in 0..<bmp.width where x >= bmp.width * 80 / 240 && x <= bmp.width * 160 / 240 {
            mask[y * bmp.width + x] = true
        } }
        let before = RouteScanner.palette(in: image)
        let after = RouteScanner.palette(in: image, excluding: mask)
        let tanLab = Lab(r: 179, g: 135, b: 97)
        #expect(before.contains { $0.lab.distance(to: tanLab) < 20 })
        #expect(!after.contains { $0.lab.distance(to: tanLab) < 20 }, "\(after.map(\.hex))")
        #expect(after.contains { $0.lab.distance(to: Lab(r: 255, g: 0, b: 0)) < 20 })
    }

    /// A Vision mask is resampled to the bitmap's size, and an empty one
    /// is nil so the scan reads the wall as before.
    @Test func masksResample() throws {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_OneComponent8, nil, &pb)
        let buffer = try #require(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<4 { for x in 0..<4 { base[y * bpr + x] = x >= 2 ? 255 : 0 } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let mask = try #require(PeopleEngine.resample(buffer, width: 8, height: 2))
        #expect(mask.count == 16)
        #expect(mask[0] == false && mask[3] == false && mask[4] == true && mask[7] == true)
        CVPixelBufferLockBaseAddress(buffer, [])
        for y in 0..<4 { for x in 0..<4 { base[y * bpr + x] = 0 } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        #expect(PeopleEngine.resample(buffer, width: 8, height: 2) == nil)
    }
}
