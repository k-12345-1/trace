import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClimbingApp

/// A hold's outline hugs the hold, where a box only contains it.
@Suite("Hold outlines")
struct OutlineTests {
    /// A grey wall with one round red hold on it.
    private func wall(radius: Double) -> CGImage {
        let size = 200
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return r.image { ctx in
            UIColor(white: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.red.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 100 - radius, y: 100 - radius, width: radius * 2, height: radius * 2))
        }.cgImage!
    }

    private func area(_ poly: [CGPoint]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var a = 0.0
        for i in poly.indices {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            a += p.x * q.y - q.x * p.y
        }
        return abs(a) / 2
    }

    @Test func aRoundHoldGetsARoundOutline() throws {
        let holds = RouteScanner.detectHolds(in: wall(radius: 20), color: Lab(r: 255, g: 0, b: 0))
        let hold = try #require(holds.first)
        #expect(hold.outline.count >= 8, "\(hold.outline.count) points")
        // Inside the box, and well under its area: a circle is 79% of its square.
        for p in hold.outline { #expect(hold.rect.insetBy(dx: -0.01, dy: -0.01).contains(p)) }
        let boxArea = Double(hold.rect.width * hold.rect.height)
        #expect(area(hold.outline) < boxArea * 0.9)
        #expect(area(hold.outline) > boxArea * 0.6)
    }

    @Test func aTappedHoldHasAnOutlineToo() throws {
        let hold = try #require(RouteScanner.hold(in: wall(radius: 20), at: CGPoint(x: 0.5, y: 0.5)))
        #expect(hold.outline.count >= 8)
    }

    @Test func theHullIsConvexAndOrdered() {
        let square = [(0, 0), (10, 0), (10, 10), (0, 10), (5, 5), (2, 7)]
        let h = RouteScanner.hull(square)
        #expect(h.count == 4)
        #expect(!h.contains { $0 == (5, 5) || $0 == (2, 7) })
    }

    /// A route saved before outlines existed still opens and draws boxes.
    @Test func anOldRouteDecodesWithoutOutlines() throws {
        let json = """
        {"id":"\(UUID().uuidString)","gymID":"\(UUID().uuidString)","name":"r","grade":"","colorHex":"#FF0000",
         "photoFilename":"p.jpg","holds":[[[0.1,0.1],[0.05,0.05]]],"scannedAt":0,"sent":false,"note":""}
        """.data(using: .utf8)!
        let route = try JSONDecoder().decode(Route.self, from: json)
        #expect(route.outlines == nil)
        #expect(route.outline(at: 0) == nil)
    }
}

/// A photograph taken on its side is read the way up it is shown.
@Suite("Upright photographs")
struct UprightTests {
    @Test func aSidewaysStillComesUpright() {
        let w = 300, h = 200
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f)
        let raw = r.image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }.cgImage!
        // Stored sideways: the pixels are 300 by 200, the picture is shown 200 by 300.
        let sideways = UIImage(cgImage: raw, scale: 1, orientation: .right)
        #expect(sideways.cgImage!.width == 300)
        let up = sideways.upright
        #expect(up.cgImage!.width == 200 && up.cgImage!.height == 300)
        #expect(up.imageOrientation == .up)
        // The red square was top-left in the buffer; rotated right it is top-right.
        let hold = RouteScanner.hold(in: up.cgImage!, at: CGPoint(x: 0.9, y: 0.1))
        #expect(hold != nil)
        #expect(RouteScanner.hold(in: up.cgImage!, at: CGPoint(x: 0.1, y: 0.1)) == nil)
    }

    @Test func anUprightPhotoIsLeftAlone() {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let ui = r.image { ctx in UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50)) }
        #expect(ui.upright === ui)
    }
}
