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

/// What is not a hold, and what shape a hold has.
@Suite("Hold shapes and patches")
struct HoldShapeRuleTests {
    private func canvas(_ draw: (CGContext) -> Void) -> CGImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240), format: f).image { ctx in
            UIColor(white: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
            draw(ctx.cgContext)
        }.cgImage!
    }
    private func area(_ poly: [CGPoint]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var a = 0.0
        for i in poly.indices { let p = poly[i], q = poly[(i + 1) % poly.count]; a += p.x * q.y - q.x * p.y }
        return abs(a) / 2
    }

    /// The outline follows a U into its bend. The defect: a hull bridged it.
    @Test func aUShapedHoldKeepsItsBend() throws {
        let image = canvas { c in
            c.setFillColor(UIColor.red.cgColor)
            // Under the sheet limit: a hold is a small share of a wall.
            c.fill(CGRect(x: 90, y: 90, width: 12, height: 44))
            c.fill(CGRect(x: 128, y: 90, width: 12, height: 44))
            c.fill(CGRect(x: 90, y: 122, width: 50, height: 12))
        }
        let hold = try #require(RouteScanner.detectHolds(in: image, color: Lab(r: 255, g: 0, b: 0)).first)
        let traced = area(hold.outline)
        let boxArea = Double(hold.rect.width * hold.rect.height)
        // The U covers 48% of its box; a hull would cover nearly all of it.
        #expect(traced < boxArea * 0.7, "\(traced / boxArea)")
        #expect(traced > boxArea * 0.3)
    }

    /// A ring is not a lump.
    @Test func aRingOfGlareIsNotAHold() {
        let image = canvas { c in
            c.setFillColor(UIColor.red.cgColor)
            c.fillEllipse(in: CGRect(x: 70, y: 70, width: 100, height: 100))
            c.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: 77, y: 77, width: 86, height: 86))
        }
        #expect(RouteScanner.detectHolds(in: image, color: Lab(r: 255, g: 0, b: 0)).isEmpty)
    }

    /// Chalk on a green hold is not a white hold.
    @Test func aPatchOnAnotherRoutesHoldIsNotAHold() throws {
        let image = canvas { c in
            c.setFillColor(UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: 60, y: 60, width: 100, height: 100))
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: 95, y: 95, width: 30, height: 30))   // chalk on the green
            c.fillEllipse(in: CGRect(x: 180, y: 180, width: 30, height: 30)) // a white hold on the wall
        }
        let bmp = try #require(Bitmap(image, targetWidth: 240))
        let green = Lab(r: 51, g: 153, b: 51), white = Lab(r: 255, g: 255, b: 255)
        var labels = RouteScanner.segment(bmp, colors: [green, white], tolerance: 30)
        let whites = RouteScanner.holds(in: bmp, labels: &labels, index: 1, colors: [green, white])
        #expect(whites.count == 1, "\(whites.count)")
        #expect(whites.first.map { $0.rect.midX > 0.6 } == true)
    }

    /// Writing on a hold means it is not a hold, and a colour that was only
    /// stickers is not a route.
    @Test func stickersAreNotHolds() {
        func hold(_ x: Double, _ y: Double) -> RouteScanner.Hold {
            RouteScanner.Hold(rect: CGRect(x: x, y: y, width: 0.04, height: 0.03), area: 0.0012)
        }
        let yellow = RouteScanner.Swatch(hex: "#FFFF00", lab: Lab(r: 255, g: 255, b: 0),
                                         holds: [hold(0.1, 0.1), hold(0.5, 0.5), hold(0.8, 0.8)], score: 1)
        let green = RouteScanner.Swatch(hex: "#00AA00", lab: Lab(r: 0, g: 170, b: 0),
                                        holds: [hold(0.2, 0.2), hold(0.3, 0.3), hold(0.4, 0.4), hold(0.6, 0.6)], score: 1)
        let text = [CGRect(x: 0.1, y: 0.1, width: 0.04, height: 0.03), CGRect(x: 0.5, y: 0.5, width: 0.04, height: 0.03),
                    CGRect(x: 0.8, y: 0.8, width: 0.04, height: 0.03), CGRect(x: 0.6, y: 0.6, width: 0.03, height: 0.02)]
        let kept = RouteScanner.withoutStickers([yellow, green], text: text)
        #expect(kept.count == 1)
        #expect(kept.first?.hex == "#00AA00")
        #expect(kept.first?.holds.count == 3)
    }
}
