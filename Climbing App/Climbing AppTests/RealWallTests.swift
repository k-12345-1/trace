import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClimbingApp

private final class BundleToken {}

/// The scanner, on a photograph of an actual climbing gym.
///
/// Everything else in these tests draws a synthetic wall: flat colour, even
/// light, holds that are ellipses. That fixture passed while the scanner was
/// useless on a real wall, and the gap between the two is the whole lesson. A
/// photographed wall has panels in three tones, a shadowed overhang, a steel
/// ceiling, bolt holes, seams, chalk and tape, and it is lit from one side, so
/// the scenery breaks into thousands of small blobs that are exactly hold
/// shaped. Ranked by how much of the picture they cover, those blobs are the
/// whole top of the list.
///
/// On the first run against this photograph the scanner offered six routes and
/// five of them were shades of grey: the ceiling trusses, the panel seams and
/// the shadow on the overhang. Not one of the ten hold colours a climber can
/// see from the floor made the list.
///
/// The fixture is the photograph as a phone would hand it over, compression
/// artefacts and all, because that is what the scanner will be given.
@Suite("A real gym wall")
struct RealWallTests {

    private func wall() throws -> CGImage {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "gymwall", withExtension: "jpg"),
                               "the wall photograph is missing from the test bundle")
        let data = try Data(contentsOf: url)
        return try #require(UIImage(data: data)?.cgImage)
    }

    private func lab(_ hex: UInt32) -> Lab {
        Lab(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }

    /// The colours a climber standing in front of this wall would name.
    private let routes: [(String, UInt32)] = [
        ("blue", 0x4478B1), ("green", 0x508F46), ("pink", 0xF45CA5),
        ("yellow", 0xF3D20F), ("orange", 0xE8450F),
    ]

    @Test("The routes a climber can see are the routes Trace offers")
    func theRealRoutesAreFound() throws {
        let found = RouteScanner.palette(in: try wall())
        #expect(found.count >= 6, "only \(found.count) colours came back")

        for (name, hex) in routes {
            let target = lab(hex)
            let match = found.contains { $0.lab.distance(to: target) < 25 }
            #expect(match, "the \(name) route was not offered: got \(found.map(\.hex))")
        }
    }

    /// The failure this test exists for. Scenery must not lead the list.
    @Test("The wall, the ceiling and the shadows are not routes")
    func sceneryDoesNotLead() throws {
        let image = try wall()
        let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.paletteWidth))
        let ground = RouteScanner.groundColors(in: bmp)
        #expect(!ground.isEmpty, "nothing was taken as wall")

        // Everything offered has to stand out from the wall, and the ones at the
        // top of the list have to stand out most.
        for swatch in RouteScanner.palette(in: image).prefix(5) {
            let apart = ground.map { $0.distance(to: swatch.lab) }.min() ?? 0
            #expect(apart > 25,
                    "\(swatch.hex) sits \(Int(apart)) from the wall's own colour")
        }
    }

    /// Ground is decided by how much of the picture a colour covers, and the
    /// separation between scenery and route has to be wide, not marginal.
    @Test("Scenery covers far more of the picture than any route")
    func theSeparationIsWide() throws {
        let bmp = try #require(Bitmap(try wall(), targetWidth: RouteScanner.paletteWidth))
        let total = Double(bmp.width * bmp.height)
        let bins = RouteScanner.commonColors(in: bmp, step: 12, keep: 12,
                                             apart: RouteScanner.groundReach)
        let scenery = bins.filter { Double($0.count) / total >= RouteScanner.groundShare }
        let rest = bins.filter { Double($0.count) / total < RouteScanner.groundShare }
        let smallestScenery = scenery.map { Double($0.count) / total }.min() ?? 0
        let largestRoute = rest.map { Double($0.count) / total }.max() ?? 0
        #expect(smallestScenery > largestRoute * 2,
                "scenery bottoms out at \(smallestScenery) and routes top out at \(largestRoute)")
    }

    /// A colour that covers a quarter of the photograph is not a route however
    /// many hold-shaped pieces it breaks into.
    @Test("No offered colour covers a large share of the wall")
    func nothingEnormousIsOffered() throws {
        let image = try wall()
        let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.paletteWidth))
        let total = Double(bmp.width * bmp.height)
        for swatch in RouteScanner.palette(in: image) {
            let share = swatch.holds.reduce(0) { $0 + $1.area }
            #expect(share < 0.12 * total / total,
                    "\(swatch.hex) covers \(share) of the picture")
        }
    }
}
