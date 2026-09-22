import Testing
import Foundation
import CoreGraphics
@testable import Spotter

/// Builds a synthetic wall: a dark background with holds of known colour and
/// known position, so what the scanner should find is known in advance.
enum Wall {
    struct Blob { var cx: Double; var cy: Double; var r: Double; var colour: (UInt8, UInt8, UInt8) }

    static let red: (UInt8, UInt8, UInt8)    = (200, 60, 45)
    static let blue: (UInt8, UInt8, UInt8)   = (50, 95, 190)
    static let yellow: (UInt8, UInt8, UInt8) = (215, 180, 50)

    /// Six red holds up the middle, four blue off to the sides, two yellow.
    static let route: [Blob] = [
        Blob(cx: 0.50, cy: 0.86, r: 0.035, colour: red),
        Blob(cx: 0.44, cy: 0.70, r: 0.032, colour: red),
        Blob(cx: 0.56, cy: 0.56, r: 0.034, colour: red),
        Blob(cx: 0.47, cy: 0.42, r: 0.030, colour: red),
        Blob(cx: 0.54, cy: 0.28, r: 0.033, colour: red),
        Blob(cx: 0.49, cy: 0.14, r: 0.036, colour: red),
        Blob(cx: 0.16, cy: 0.75, r: 0.034, colour: blue),
        Blob(cx: 0.84, cy: 0.62, r: 0.031, colour: blue),
        Blob(cx: 0.18, cy: 0.35, r: 0.033, colour: blue),
        Blob(cx: 0.82, cy: 0.22, r: 0.032, colour: blue),
        Blob(cx: 0.30, cy: 0.50, r: 0.030, colour: yellow),
        Blob(cx: 0.70, cy: 0.88, r: 0.030, colour: yellow)
    ]

    static func image(_ blobs: [Blob] = route, w: Int = 800, h: Int = 1200) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.13, green: 0.11, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        for b in blobs {
            ctx.setFillColor(CGColor(red: Double(b.colour.0) / 255,
                                     green: Double(b.colour.1) / 255,
                                     blue: Double(b.colour.2) / 255, alpha: 1))
            // Context origin is bottom left; blob coordinates are top left.
            let r = b.r * Double(w)
            ctx.fillEllipse(in: CGRect(x: b.cx * Double(w) - r,
                                       y: (1 - b.cy) * Double(h) - r,
                                       width: r * 2, height: r * 2))
        }
        return ctx.makeImage()!
    }

    /// A point inside the first blob of a given colour, in normalised top-left space.
    static func point(of colour: (UInt8, UInt8, UInt8)) -> CGPoint {
        let b = route.first { $0.colour == colour }!
        return CGPoint(x: b.cx, y: b.cy)
    }
}

@Suite("Route scanning")
struct RouteScannerTests {

    @Test("Tapping a red hold finds the red route and nothing else")
    func findsOneColour() {
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                             sample: Wall.point(of: Wall.red),
                                             tolerance: 30)
        // Six red holds were drawn, and the blue and yellow ones must not appear.
        #expect(found.holds.count == 6, "found \(found.holds.count)")

        // Every detection should sit on a red blob.
        let reds = Wall.route.filter { $0.colour == Wall.red }
        for hold in found.holds {
            let near = reds.contains { b in
                abs(b.cx - hold.rect.midX) < 0.03 && abs(b.cy - hold.rect.midY) < 0.03
            }
            #expect(near, "a detection landed away from any red hold")
        }
    }

    @Test("Tapping a blue hold finds the blue set instead")
    func picksTheTappedColour() {
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                             sample: Wall.point(of: Wall.blue),
                                             tolerance: 30)
        #expect(found.holds.count == 4, "found \(found.holds.count)")
    }

    @Test("The sampled colour is reported back for the route swatch")
    func reportsColour() {
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                             sample: Wall.point(of: Wall.blue),
                                             tolerance: 30)
        #expect(found.colorHex.hasPrefix("#"))
        // Blue channel should dominate in what was sampled.
        let hex = found.colorHex.dropFirst()
        let r = UInt8(hex.prefix(2), radix: 16) ?? 0
        let b = UInt8(hex.suffix(2), radix: 16) ?? 0
        #expect(b > r, "expected a blue-dominant sample, got \(found.colorHex)")
    }

    @Test("A wide colour range starts pulling in other holds")
    func toleranceWidens() {
        let tight = RouteScanner.detectHolds(in: Wall.image(),
                                              sample: Wall.point(of: Wall.red), tolerance: 14)
        let wide = RouteScanner.detectHolds(in: Wall.image(),
                                             sample: Wall.point(of: Wall.red), tolerance: 58)
        // This is why the slider exists, and why the climber gets to drop holds.
        #expect(wide.holds.count >= tight.holds.count)
    }

    @Test("Tapping bare wall finds no route")
    func emptyWall() {
        // The background is one huge connected region, which is above the area
        // ceiling, so it must not come back as a hold.
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                              sample: CGPoint(x: 0.03, y: 0.03),
                                              tolerance: 20)
        #expect(found.holds.isEmpty, "found \(found.holds.count) on bare wall")
    }

    @Test("Holds are returned largest first")
    func sortedBySize() {
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                              sample: Wall.point(of: Wall.red), tolerance: 30)
        #expect(zip(found.holds, found.holds.dropFirst()).allSatisfy { $0.area >= $1.area })
    }
}

@Suite("Colour")
struct ColourTests {

    @Test("Identical colours are zero apart")
    func identity() {
        let a = Lab(r: 200, g: 60, b: 45)
        #expect(a.distance(to: a) < 0.0001)
    }

    @Test("Red and blue are far apart, two reds are close")
    func separation() {
        let red = Lab(r: 200, g: 60, b: 45)
        let blue = Lab(r: 50, g: 95, b: 190)
        let redish = Lab(r: 208, g: 66, b: 50)
        #expect(red.distance(to: blue) > 60)
        #expect(red.distance(to: redish) < 12)
    }

    @Test("Black and white sit at the ends of the lightness axis")
    func lightness() {
        #expect(Lab(r: 0, g: 0, b: 0).l < 1)
        #expect(Lab(r: 255, g: 255, b: 255).l > 99)
    }
}

@Suite("Route tags")
struct GradeReadingTests {

    @Test("Grades are picked out of whatever is printed on the tag")
    func reads() {
        let found = RouteScanner.grades(in: ["V4", "Set 12 Mar", "Jamie", "5.11c", "7a+"])
        #expect(found.contains("V4"))
        #expect(found.contains("5.11C"))
        #expect(found.contains("7A+"))
    }

    @Test("Ordinary words are not mistaken for grades")
    func rejects() {
        let found = RouteScanner.grades(in: ["Setter", "Brooklyn Boulders", "Warm up", "2026"])
        #expect(found.isEmpty, "matched \(found)")
    }

    @Test("A bare V grade and a V-easy both read")
    func vScale() {
        #expect(RouteScanner.grades(in: ["V0"]) == ["V0"])
        #expect(RouteScanner.grades(in: ["VB"]) == ["VB"])
        #expect(RouteScanner.grades(in: ["V12"]) == ["V12"])
    }
}
