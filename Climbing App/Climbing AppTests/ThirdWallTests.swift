import Testing
import Foundation
import UIKit
import CoreGraphics
@testable import ClimbingApp

private final class WallToken {}

/// The third real wall: grey-blue panels in uneven light, and a photograph
/// with the routes traced on it by hand. The traced outlines give the truth
/// for where each route's holds are; the hand-drawn strokes are also in the
/// pixels, which is why the checks are about coverage rather than counts.
///
/// The failure this was taken for: the yellow route came back as three
/// colours, lit, shaded and chalked, each with a third of the holds, and the
/// boxes offered under "yellow" sat on orange holds, a green one and the mat.
@Suite("A third real wall")
struct ThirdWallTests {
    private func wall() throws -> CGImage {
        let url = try #require(Bundle(for: WallToken.self).url(forResource: "wall3", withExtension: "jpg"))
        return try #require(UIImage(data: Data(contentsOf: url))?.cgImage)
    }

    private func lab(_ hex: UInt32) -> Lab {
        Lab(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }

    /// Each route a person names on this wall, a colour for it, and points,
    /// normalised, in the middle of holds the tracing says are its.
    private let routes: [(String, UInt32, [CGPoint])] = [
        ("yellow", 0xF1BC11, [CGPoint(x: 0.23, y: 0.53), CGPoint(x: 0.44, y: 0.42),
                              CGPoint(x: 0.44, y: 0.60), CGPoint(x: 0.46, y: 0.80), CGPoint(x: 0.37, y: 0.62)]),
        ("pink",   0xDB5A70, [CGPoint(x: 0.37, y: 0.17), CGPoint(x: 0.30, y: 0.27), CGPoint(x: 0.38, y: 0.38)]),
        ("orange", 0xB5533C, [CGPoint(x: 0.26, y: 0.42), CGPoint(x: 0.33, y: 0.52), CGPoint(x: 0.22, y: 0.77)]),
        ("green",  0x344B1E, [CGPoint(x: 0.62, y: 0.23), CGPoint(x: 0.55, y: 0.47), CGPoint(x: 0.45, y: 0.52)]),
        ("blue",   0x436382, [CGPoint(x: 0.72, y: 0.11), CGPoint(x: 0.26, y: 0.70), CGPoint(x: 0.25, y: 0.37)]),
    ]

    private func hue(_ l: Lab) -> Double { atan2(l.b, l.a) }

    @Test("Every route is offered once, and its boxes are on its holds")
    func theRoutesAreOfferedOnce() throws {
        let found = RouteScanner.palette(in: try wall())
        for (name, hex, points) in routes {
            let target = lab(hex)
            let nearest = found.min { $0.lab.distance(to: target) < $1.lab.distance(to: target) }
            let match = try #require(nearest.flatMap { $0.lab.distance(to: target) < 32 ? $0 : nil },
                                     "the \(name) route was not offered: got \(found.map(\.hex))")
            let covered = points.filter { p in
                match.holds.contains { $0.rect.insetBy(dx: -0.012, dy: -0.012).contains(p) }
            }.count
            #expect(covered >= points.count - 1,
                    "\(name): \(covered) of \(points.count) known holds boxed, \(match.holds.count) boxes")
        }
    }

    /// Lit, shaded and chalked yellow are one yellow.
    @Test("No two offered colours are shades of one hue")
    func shadesAreJoined() throws {
        let found = RouteScanner.palette(in: try wall())
        for i in found.indices {
            for j in found.indices where j > i {
                let a = found[i].lab, b = found[j].lab
                let ca = (a.a * a.a + a.b * a.b).squareRoot(), cb = (b.a * b.a + b.b * b.b).squareRoot()
                guard ca >= RouteScanner.familyMinChroma, cb >= RouteScanner.familyMinChroma else { continue }
                var dh = abs(hue(a) - hue(b)); if dh > .pi { dh = 2 * .pi - dh }
                let ratio = max(ca, cb) / min(ca, cb)
                #expect(!(dh < RouteScanner.familyHue && ratio <= RouteScanner.familyChroma),
                        "\(found[i].hex) and \(found[j].hex) are shades of one hue")
            }
        }
    }

    @Test("The yellow route has its holds")
    func yellowIsWhole() throws {
        let found = RouteScanner.palette(in: try wall())
        let yellow = try #require(found.min { $0.lab.distance(to: lab(0xF1BC11)) < $1.lab.distance(to: lab(0xF1BC11)) })
        #expect(yellow.holds.count >= 14, "\(yellow.holds.count)")
    }
}
