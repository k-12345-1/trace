import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClimbingApp

private final class CoverToken {}

/// Whether the photograph holds the whole route.
@Suite("Route coverage")
struct CoverageTests {
    private func hold(_ x: Double, _ y: Double, _ s: Double = 0.05) -> CGRect {
        CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
    }
    private func tag(_ kind: RouteScanner.Tag.Kind, _ x: Double, _ y: Double) -> RouteScanner.Tag {
        RouteScanner.Tag(kind: kind, point: CGPoint(x: x, y: y))
    }

    @Test func aRouteInTheMiddleLooksWhole() {
        let c = CoverageEngine.read(holds: [hold(0.5, 0.8), hold(0.45, 0.6), hold(0.5, 0.4)])
        #expect(c.looksComplete)
        #expect(c.sentence == nil)
    }

    @Test func aHoldCutByTheFrameContinuesThatWay() {
        let c = CoverageEngine.read(holds: [hold(0.5, 0.8), CGRect(x: 0, y: 0.5, width: 0.04, height: 0.05)])
        #expect(c.continues == [.left])
        #expect(c.sentence?.contains("to the left") == true)
    }

    @Test func aLineHeadingIntoAnEdgeContinues() {
        let c = CoverageEngine.read(holds: [hold(0.5, 0.8), hold(0.3, 0.6), hold(0.1, 0.5)])
        #expect(c.continues.contains(.left))
        let up = CoverageEngine.read(holds: [hold(0.5, 0.8), hold(0.5, 0.5), hold(0.5, 0.04)])
        #expect(up.continues.contains(.above))
    }

    /// A finish sticker on the top hold is the route ending, however close
    /// to the edge it is.
    @Test func aFinishStickerSettlesTheTop() {
        let holds = [hold(0.5, 0.8), hold(0.5, 0.5), hold(0.5, 0.04)]
        let c = CoverageEngine.read(holds: holds, tags: [tag(.finish, 0.52, 0.07), tag(.start, 0.5, 0.84)])
        #expect(c.sawFinish && c.sawStart)
        #expect(c.looksComplete)
    }

    /// Start seen, no finish, and the top hold near the edge: the top is not
    /// in the picture.
    @Test func aStartWithoutAFinishContinuesAbove() {
        let holds = [hold(0.5, 0.8), hold(0.5, 0.5), hold(0.5, 0.25)]
        let c = CoverageEngine.read(holds: holds, tags: [tag(.start, 0.5, 0.84), tag(.finish, 0.9, 0.1)])
        #expect(c.sawStart && !c.sawFinish)
        #expect(c.continues.contains(.above))
    }

    @Test func stickersOnOtherRoutesSayNothing() {
        let holds = [hold(0.5, 0.8), hold(0.5, 0.6), hold(0.5, 0.4)]
        let c = CoverageEngine.read(holds: holds, tags: [tag(.start, 0.1, 0.9), tag(.finish, 0.9, 0.1)])
        #expect(c.looksComplete && !c.sawStart && !c.sawFinish)
        // And a sticker nearer another route's hold is that route's.
        let shared = CoverageEngine.read(holds: holds, tags: [tag(.start, 0.5, 0.86)], others: [hold(0.5, 0.845)])
        #expect(!shared.sawStart)
    }

    @Test func theSentenceListsEdges() {
        let c = CoverageEngine.Coverage(continues: [.left, .above], sawStart: false, sawFinish: false, tagsRead: false)
        #expect(c.sentence?.hasPrefix("Probably continues to the left and above.") == true)
    }

    /// The fourth wall, as the climber read it: blue and pink are whole, the
    /// green and yellow routes run off the left of the picture, the black
    /// route off the right.
    @Test("The fourth real wall says which routes leave the picture")
    func theFourthWall() throws {
        let url = try #require(Bundle(for: CoverToken.self).url(forResource: "wall4", withExtension: "jpg"))
        let image = try #require(UIImage(data: Data(contentsOf: url))?.cgImage)
        let found = RouteScanner.palette(in: image)
        func lab(_ hex: UInt32) -> Lab {
            Lab(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
        }
        func route(_ hex: UInt32, _ name: String) throws -> RouteScanner.Swatch {
            let t = lab(hex)
            let best = found.min { $0.lab.distance(to: t) < $1.lab.distance(to: t) }
            return try #require(best.flatMap { $0.lab.distance(to: t) < 34 ? $0 : nil },
                                "\(name) was not offered: \(found.map(\.hex))")
        }
        let blue = try route(0x2D759F, "blue"), pink = try route(0xD16C7A, "pink")
        let green = try route(0x3B6121, "green"), yellow = try route(0xF2DE17, "yellow")
        let black = try route(0x2B2B2B, "black")
        // The stickers, where they are in the photograph. Vision reads
        // nothing in the simulator, so they are given here.
        let tags = [tag(.finish, 0.33, 0.15), tag(.finish, 0.46, 0.17), tag(.finish, 0.53, 0.10),
                    tag(.start, 0.15, 0.70), tag(.start, 0.45, 0.73), tag(.start, 0.77, 0.79),
                    tag(.start, 0.57, 0.83), tag(.finish, 0.05, 0.19)]
        func read(_ s: RouteScanner.Swatch) -> CoverageEngine.Coverage {
            let others = found.filter { $0.id != s.id }.flatMap { $0.holds.map(\.rect) }
            return CoverageEngine.read(holds: s.holds.map(\.rect), tags: tags, others: others)
        }
        let b = read(blue)
        #expect(b.sawStart && b.sawFinish && b.looksComplete, "\(b)")
        let p = read(pink)
        #expect(p.sawFinish && !p.continues.contains(.left) && !p.continues.contains(.above), "\(p)")
        let g = read(green)
        #expect(g.continues.contains(.left), "\(g)")
        let y = read(yellow)
        #expect(y.continues.contains(.left) && y.sawStart && !y.sawFinish, "\(y)")
        let k = read(black)
        #expect(k.continues.contains(.right), "\(k)")
        #expect(black.holds.count >= 8, "\(black.holds.count)")
    }
}

/// A tag beside its hold is the hold's.
@Suite("Tags beside holds")
struct TagBesideTests {
    @Test func aStickerBesideAHoldNamesIt() {
        // A big start jug with the Start sticker to its right, level with
        // its middle, and a chip well above.
        let jug = CGRect(x: 0.40, y: 0.60, width: 0.08, height: 0.06)
        let chip = CGRect(x: 0.42, y: 0.40, width: 0.02, height: 0.02)
        let tag = RouteScanner.Tag(kind: .start, point: CGPoint(x: 0.50, y: 0.64))
        #expect(CoverageEngine.holdIndex(for: tag, holds: [chip, jug]) == 1)
        #expect(CoverageEngine.startHolds(holds: [chip, jug], tags: [tag]) == [1])
    }
}
