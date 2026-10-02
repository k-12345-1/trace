import Testing
import Foundation
import UIKit
@testable import ClimbingApp

private final class WallToken {}

/// What is true of every route on every real wall, whatever the wall.
@Suite("Scanner invariants on real walls")
struct ScanInvariantTests {
    private func wall(_ name: String) throws -> (CGImage, Bitmap) {
        let url = try #require(Bundle(for: WallToken.self).url(forResource: name, withExtension: "jpg"))
        let image = try #require(UIImage(data: Data(contentsOf: url))?.upright.cgImage)
        return (image, try #require(Bitmap(image, targetWidth: RouteScanner.workingWidth)))
    }

    @Test(arguments: ["gymwall", "wall2", "wall3", "wall4", "wall5", "wall6"])
    func everyRouteIsWellFormed(_ name: String) throws {
        let (image, bmp) = try wall(name)
        let reading = FaceEngine.read(in: bmp)
        let routes = RouteScanner.onTheWall(RouteScanner.palette(in: image), reading: reading, width: bmp.width, height: bmp.height)
        #expect(routes.count >= 4, "\(name): \(routes.count) routes")
        for r in routes {
            #expect(r.holds.count >= RouteScanner.minimumHolds, "\(name) \(r.hex)")
            for h in r.holds {
                // On the picture, hold sized, with a closed outline in its box.
                #expect(h.rect.minX >= 0 && h.rect.minY >= 0 && h.rect.maxX <= 1.001 && h.rect.maxY <= 1.001, "\(name) \(r.hex) \(h.rect)")
                #expect(h.area <= RouteScanner.maxAreaFraction * 2.5, "\(name) \(r.hex) area \(h.area)")
                #expect(h.outline.count >= 3, "\(name) \(r.hex) outline")
                for p in h.outline {
                    #expect(h.rect.insetBy(dx: -0.01, dy: -0.01).contains(p), "\(name) \(r.hex) outline point off its box")
                    #expect(!p.x.isNaN && !p.y.isNaN)
                }
                // On the wall: not above the top, not below the mat.
                #expect(reading.onTheWall(CGPoint(x: h.rect.midX, y: h.rect.midY), width: bmp.width, height: bmp.height), "\(name) \(r.hex) off the wall")
            }
            // No hold drawn twice: a small hold may sit inside a big one's
            // box, a hold in the bay of a snake or on a volume's face, but
            // not on the same centre.
            for (i, a) in r.holds.enumerated() {
                for b in r.holds[(i + 1)...] where i + 1 < r.holds.count {
                    let apart = hypot(a.rect.midX - b.rect.midX, a.rect.midY - b.rect.midY)
                    let nested = a.rect.contains(b.rect) || b.rect.contains(a.rect)
                    #expect(!(nested && apart < RouteScanner.shardCentre), "\(name) \(r.hex) two holds on one spot at \(a.rect.midX), \(a.rect.midY)")
                }
            }
        }
        // Two offered colours are not shades of one hue.
        for (i, a) in routes.enumerated() {
            for b in routes[(i + 1)...] where i + 1 < routes.count {
                #expect(a.lab.distance(to: b.lab) > 12, "\(name): \(a.hex) and \(b.hex) are one colour")
            }
        }
    }
}
