import Testing
import Foundation
import UIKit
@testable import ClimbingApp

private final class WallToken {}

/// The fifth real wall: grey panels under warm light, a cream route, and
/// a lot of chalk. The lit panel at the top left and a chalk streak on the
/// right both read as cream, and came back as the cream route's biggest
/// holds. A hold stands clear of the wall; those did not.
@Suite("A fifth real wall")
struct FifthWallTests {
    private func wall() throws -> CGImage {
        let url = try #require(Bundle(for: WallToken.self).url(forResource: "wall5", withExtension: "jpg"))
        return try #require(UIImage(data: Data(contentsOf: url))?.upright.cgImage)
    }

    @Test("The lit panel and the chalk streak are not cream holds")
    func wallIsNotARoute() throws {
        let found = RouteScanner.palette(in: try wall())
        let cream = Lab(hexString: "#EAC89F")
        let route = try #require(found.min { $0.lab.distance(to: cream) < $1.lab.distance(to: cream) })
        #expect(route.lab.distance(to: cream) < 20, "\(route.hex)")
        // The panel covered 4% of the picture at the top left; the streak
        // sat at x 0.76, y 0.45.
        #expect(!route.holds.contains { $0.area > 0.02 })
        #expect(!route.holds.contains { $0.rect.contains(CGPoint(x: 0.76, y: 0.45)) && $0.area > 0.003 })
        // The three cream volumes in the middle of the wall are kept.
        for p in [CGPoint(x: 0.49, y: 0.36), CGPoint(x: 0.64, y: 0.57), CGPoint(x: 0.81, y: 0.70)] {
            #expect(route.holds.contains { $0.rect.contains(p) }, "\(p)")
        }
        #expect(route.holds.count <= 25, "\(route.holds.count)")
    }
}
