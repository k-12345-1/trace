import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Builds a synthetic wall: a dark background with holds of known color and
/// known position, so what the scanner should find is known in advance.
enum Wall {
    struct Blob { var cx: Double; var cy: Double; var r: Double; var color: (UInt8, UInt8, UInt8) }

    static let red: (UInt8, UInt8, UInt8)    = (200, 60, 45)
    static let blue: (UInt8, UInt8, UInt8)   = (50, 95, 190)
    static let yellow: (UInt8, UInt8, UInt8) = (215, 180, 50)

    /// Six red holds up the middle, four blue off to the sides, two yellow.
    static let route: [Blob] = [
        Blob(cx: 0.50, cy: 0.86, r: 0.035, color: red),
        Blob(cx: 0.44, cy: 0.70, r: 0.032, color: red),
        Blob(cx: 0.56, cy: 0.56, r: 0.034, color: red),
        Blob(cx: 0.47, cy: 0.42, r: 0.030, color: red),
        Blob(cx: 0.54, cy: 0.28, r: 0.033, color: red),
        Blob(cx: 0.49, cy: 0.14, r: 0.036, color: red),
        Blob(cx: 0.16, cy: 0.75, r: 0.034, color: blue),
        Blob(cx: 0.84, cy: 0.62, r: 0.031, color: blue),
        Blob(cx: 0.18, cy: 0.35, r: 0.033, color: blue),
        Blob(cx: 0.82, cy: 0.22, r: 0.032, color: blue),
        Blob(cx: 0.30, cy: 0.50, r: 0.030, color: yellow),
        Blob(cx: 0.70, cy: 0.88, r: 0.030, color: yellow)
    ]

    static func image(_ blobs: [Blob] = route, w: Int = 800, h: Int = 1200) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.13, green: 0.11, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        for b in blobs {
            ctx.setFillColor(CGColor(red: Double(b.color.0) / 255,
                                     green: Double(b.color.1) / 255,
                                     blue: Double(b.color.2) / 255, alpha: 1))
            // Context origin is bottom left; blob coordinates are top left.
            let r = b.r * Double(w)
            ctx.fillEllipse(in: CGRect(x: b.cx * Double(w) - r,
                                       y: (1 - b.cy) * Double(h) - r,
                                       width: r * 2, height: r * 2))
        }
        return ctx.makeImage()!
    }

    /// A point inside the first blob of a given color, in normalized top-left space.
    static func point(of color: (UInt8, UInt8, UInt8)) -> CGPoint {
        let b = route.first { $0.color == color }!
        return CGPoint(x: b.cx, y: b.cy)
    }
}

@Suite("Route scanning")
struct RouteScannerTests {

    @Test("Tapping a red hold finds the red route and nothing else")
    func findsOneColor() {
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                             sample: Wall.point(of: Wall.red),
                                             tolerance: 30)
        // Six red holds were drawn, and the blue and yellow ones must not appear.
        #expect(found.holds.count == 6, "found \(found.holds.count)")

        // Every detection should sit on a red blob.
        let reds = Wall.route.filter { $0.color == Wall.red }
        for hold in found.holds {
            let near = reds.contains { b in
                abs(b.cx - hold.rect.midX) < 0.03 && abs(b.cy - hold.rect.midY) < 0.03
            }
            #expect(near, "a detection landed away from any red hold")
        }
    }

    @Test("Tapping a blue hold finds the blue set instead")
    func picksTheTappedColor() {
        let found = RouteScanner.detectHolds(in: Wall.image(),
                                             sample: Wall.point(of: Wall.blue),
                                             tolerance: 30)
        #expect(found.holds.count == 4, "found \(found.holds.count)")
    }

    @Test("The sampled color is reported back for the route swatch")
    func reportsColor() {
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

    @Test("A wide color range starts pulling in other holds")
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

@Suite("Color")
struct ColorTests {

    @Test("Identical colors are zero apart")
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

/// Reading the wall's colors instead of being told one.
///
/// Tapping a hold asks the climber to do the computer's job: land a finger on a
/// hold precisely enough to sample its color rather than its shadow, and then
/// work a tolerance slider when it went wrong. A gym sets routes in colors, and
/// the colors are the first thing anybody sees standing at the bottom of the
/// wall, so Trace reads them itself and offers them.
@Suite("Reading a wall's colors")
struct PaletteTests {

    private func palette() -> [RouteScanner.Swatch] {
        RouteScanner.palette(in: Wall.image())
    }

    @Test("The routes on the wall come back as colors")
    func theWallReadsAsRoutes() {
        let found = palette()
        #expect(found.count >= 2, "found \(found.count) colors")
    }

    /// The red route is six holds from the floor to the top. The blue is four
    /// scattered up the sides. Both are real, and red is the better answer.
    @Test("The route with the most holds up the wall leads")
    func theBestRouteIsFirst() throws {
        let best = try #require(palette().first)
        #expect(best.holds.count >= 5, "the leading color had \(best.holds.count) holds")
        #expect(Lab(r: Wall.red.0, g: Wall.red.1, b: Wall.red.2)
                    .distance(to: best.lab) < 30,
                "the leading color was \(best.hex), not the red route")
    }

    /// The whole reason this can work without being told what the wall is. Wall,
    /// mats and floor are the most common colors in the photograph by a mile,
    /// and they come back as one enormous blob each, which is not a hold.
    @Test("The wall itself is not offered as a route")
    func theWallIsNotARoute() {
        let wall = Lab(r: 33, g: 28, b: 26)
        for swatch in palette() {
            #expect(swatch.lab.distance(to: wall) > 20,
                    "the background came back as a route: \(swatch.hex)")
        }
    }

    /// Two holds of a color is somebody's logo on the mat, or two holds of
    /// another route that happen to match. It is not a route.
    @Test("Two holds of a color is not a route")
    func twoHoldsIsNotARoute() {
        let yellow = Lab(r: Wall.yellow.0, g: Wall.yellow.1, b: Wall.yellow.2)
        #expect(!palette().contains { $0.lab.distance(to: yellow) < 25 },
                "two yellow holds were offered as a route")
    }

    /// Every swatch has to be able to find its own holds again at full
    /// resolution, because that is what happens the moment one is chosen.
    @Test("Choosing a swatch finds the same route again")
    func aSwatchFindsItsRouteAgain() throws {
        let best = try #require(palette().first)
        let again = RouteScanner.detectHolds(in: Wall.image(), color: best.lab)
        #expect(again.count >= best.holds.count - 1,
                "the swatch found \(best.holds.count) holds and the full pass found \(again.count)")
    }

    /// Spread up the wall is what separates a route from a bank of volumes in
    /// one corner, so it has to count for something.
    @Test("Holds spread up the wall beat holds in a corner")
    func spreadBeatsClustering() {
        func hold(_ x: Double, _ y: Double) -> RouteScanner.Hold {
            RouteScanner.Hold(rect: CGRect(x: x, y: y, width: 0.04, height: 0.04), area: 0.001)
        }
        let spread = (0..<6).map { hold(0.5, 0.1 + Double($0) * 0.15) }
        let corner = (0..<6).map { hold(0.1 + Double($0) * 0.01, 0.8 + Double($0) * 0.01) }
        #expect(RouteScanner.score(spread) > RouteScanner.score(corner))
    }

    @Test("A photograph of nothing offers nothing")
    func anEmptyWallOffersNothing() {
        #expect(RouteScanner.palette(in: Wall.image([])).isEmpty)
    }
}

/// Two colors that sit near each other in Lab have to stay apart on the wall.
@Suite("Colors that are close together")
struct NeighbourTests {

    /// A red route and an orange one, close enough that one generous mask takes
    /// both. Each color has to pull its reach in until it stops at the other.
    private static let twoTones: [Wall.Blob] = {
        let red: (UInt8, UInt8, UInt8) = (205, 55, 45)
        let orange: (UInt8, UInt8, UInt8) = (225, 115, 40)
        var blobs: [Wall.Blob] = []
        for i in 0..<6 {
            blobs.append(Wall.Blob(cx: 0.42, cy: 0.88 - Double(i) * 0.14, r: 0.034, color: red))
            blobs.append(Wall.Blob(cx: 0.66, cy: 0.84 - Double(i) * 0.14, r: 0.033, color: orange))
        }
        return blobs
    }()

    @Test("Two close colors come back as two routes, not one")
    func closeColorsStaySeparate() {
        let found = RouteScanner.palette(in: Wall.image(Self.twoTones))
        #expect(found.count >= 2, "found \(found.count) colors on a wall with two routes")
        // Neither route is the whole wall: twelve holds in one swatch would be
        // both routes wearing one color.
        for swatch in found.prefix(2) {
            #expect(swatch.holds.count <= 9,
                    "one color took \(swatch.holds.count) of the twelve holds")
        }
    }

    /// The chip says a number. Pressing it has to produce that number.
    @Test("A swatch counts the holds you get when you choose it")
    func theCountOnTheChipIsTheCountYouGet() throws {
        let image = Wall.image(Self.twoTones)
        let best = try #require(RouteScanner.palette(in: image).first)
        let again = RouteScanner.detectHolds(in: image, color: best.lab, tolerance: best.reach)
        #expect(abs(again.count - best.holds.count) <= 1,
                "the chip said \(best.holds.count) and choosing it gave \(again.count)")
    }

    /// With nothing else nearby a color keeps the full default reach, which is
    /// what finds the shadowed side of a hold.
    @Test("A color on its own keeps its full reach")
    func aLonelyColorStaysGenerous() throws {
        let best = try #require(RouteScanner.palette(in: Wall.image()).first)
        #expect(best.reach > 20, "a color with no neighbour was pulled in to \(best.reach)")
    }
}
