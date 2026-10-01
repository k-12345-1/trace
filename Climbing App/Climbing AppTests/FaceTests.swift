import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClimbingApp

private final class FaceToken {}

/// The seams between a wall's panels, and which panel a route is on.
@Suite("Wall faces")
struct FaceTests {
    private func canvas(_ draw: (CGContext) -> Void) -> Bitmap {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: f).image { ctx in
            UIColor(white: 0.6, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            draw(ctx.cgContext)
        }.cgImage!
        return Bitmap(img, targetWidth: 300)!
    }

    @Test func aDarkDiagonalIsASeam() throws {
        let bmp = canvas { c in
            c.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 320)); c.addLine(to: CGPoint(x: 300, y: 40)); c.strokePath()
        }
        let lines = FaceEngine.lines(in: bmp, wallL: 64)
        #expect(lines.count == 1, "\(lines.count)")
        let (a, b) = try #require(lines.first?.endpoints(width: bmp.width, height: bmp.height))
        let ends = [a, b].sorted { $0.x < $1.x }
        #expect(abs(ends[0].y - 0.8) < 0.06 && abs(ends[1].y - 0.1) < 0.06, "\(ends)")
    }

    /// A row of bolt holes is not a seam, and a shadowed panel is not one either.
    @Test func boltHolesAndSheetsAreNotSeams() {
        let holes = canvas { c in
            c.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
            for y in stride(from: 20, to: 400, by: 25) { for x in stride(from: 20, to: 300, by: 25) {
                c.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
            } }
        }
        #expect(FaceEngine.lines(in: holes, wallL: 64).isEmpty)
        let sheet = canvas { c in
            c.setFillColor(UIColor(white: 0.3, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 150, height: 400))
        }
        // The edge of the sheet is a seam; its inside is not a fan of them.
        #expect(FaceEngine.lines(in: sheet, wallL: 64).count <= 1)
    }

    /// The mat meeting the wall is not a seam, and neither is the ceiling.
    @Test func theFloorIsNotASeam() {
        let bmp = canvas { c in
            c.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 350)); c.addLine(to: CGPoint(x: 300, y: 330)); c.strokePath()
        }
        #expect(FaceEngine.lines(in: bmp, wallL: 64).isEmpty)
        // Nor is the wall meeting the ceiling.
        let top = canvas { c in
            c.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 80)); c.addLine(to: CGPoint(x: 300, y: 60)); c.strokePath()
        }
        #expect(FaceEngine.lines(in: top, wallL: 64).isEmpty)
        // The same tilt across the middle is a roof's lip, and counts.
        let lip = canvas { c in
            c.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 210)); c.addLine(to: CGPoint(x: 300, y: 190)); c.strokePath()
        }
        #expect(FaceEngine.lines(in: lip, wallL: 64).count == 1)
    }

    @Test func holdsOnTheFarSideAreSetAside() {
        let line = FaceEngine.Line(theta: 0, rho: 150, support: 1)   // x = 150 of 300
        func hold(_ x: Double, _ y: Double) -> RouteScanner.Hold {
            RouteScanner.Hold(rect: CGRect(x: x - 0.02, y: y - 0.02, width: 0.04, height: 0.04), area: 0.001)
        }
        let holds = [hold(0.6, 0.2), hold(0.7, 0.4), hold(0.65, 0.6), hold(0.8, 0.8), hold(0.2, 0.5)]
        let split = FaceEngine.split(holds, lines: [line], width: 300, height: 400)
        #expect(split.kept.count == 4 && split.aside.count == 1)
        #expect(split.aside.first?.rect.midX == 0.2)
        // Two panels each with a real share keep both.
        let both = FaceEngine.split(holds + [hold(0.1, 0.3), hold(0.3, 0.7)], lines: [line], width: 300, height: 400)
        #expect(both.aside.isEmpty)
        #expect(FaceEngine.split(holds, lines: [], width: 300, height: 400).aside.isEmpty)
    }

    /// The fifth wall: the seam between its slab and its vertical panel,
    /// running from the left edge most of the way down to the right edge
    /// near the top.
    @Test("The fifth wall has its seam")
    func theFifthWall() throws {
        let url = try #require(Bundle(for: FaceToken.self).url(forResource: "wall5", withExtension: "jpg"))
        let image = try #require(UIImage(data: Data(contentsOf: url))?.cgImage)
        let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.workingWidth))
        let lines = FaceEngine.lines(in: bmp)
        #expect(lines.count <= FaceEngine.mostLines)
        // No floor: the mat's edge runs across the bottom of this picture.
        for l in lines { #expect(!FaceEngine.isFloor(l, width: bmp.width, height: bmp.height)) }
        #expect(!lines.contains { l in
            guard let (a, b) = l.endpoints(width: bmp.width, height: bmp.height) else { return false }
            return abs(l.theta * 180 / .pi - 90) <= 25 && (a.y + b.y) / 2 > 0.8
        })
        // The seam between the slab and the vertical panel, among the right
        // panel's edge.
        let seam = lines.compactMap { $0.endpoints(width: bmp.width, height: bmp.height) }.first { a, b in
            let ends = [a, b].sorted { $0.x < $1.x }
            return ends[0].x == 0 && abs(ends[0].y - 0.88) < 0.08 && ends[1].x == 1 && abs(ends[1].y - 0.10) < 0.08
        }
        #expect(seam != nil, "\(lines.map { $0.endpoints(width: bmp.width, height: bmp.height).map { "\($0)" } ?? "" })")
    }

    /// The third wall: the left panel's vertical edge, the slab's two edges
    /// and the right panel's seam. Not the floor.
    @Test("The third wall's panels")
    func theThirdWall() throws {
        let url = try #require(Bundle(for: FaceToken.self).url(forResource: "wall3", withExtension: "jpg"))
        let image = try #require(UIImage(data: Data(contentsOf: url))?.cgImage)
        let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.workingWidth))
        let lines = FaceEngine.lines(in: bmp)
        #expect(lines.count >= 4, "\(lines.count)")
        let vertical = lines.first { abs($0.theta) < 0.1 || abs($0.theta - .pi) < 0.1 }
        let (a, _) = try #require(vertical?.endpoints(width: bmp.width, height: bmp.height))
        #expect(abs(a.x - 0.17) < 0.04, "\(a)")
    }
}

/// Nothing below the mat or above the wall is a hold.
@Suite("The wall's extent")
struct WallExtentTests {
    private func canvas(_ draw: (CGContext) -> Void) -> Bitmap {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: f).image { ctx in
            UIColor(white: 0.6, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            draw(ctx.cgContext)
        }.cgImage!
        return Bitmap(img, targetWidth: 300)!
    }

    @Test func theFloorAndTopAreRead() throws {
        let bmp = canvas { c in
            c.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 350)); c.addLine(to: CGPoint(x: 300, y: 340)); c.strokePath()
            c.move(to: CGPoint(x: 0, y: 60)); c.addLine(to: CGPoint(x: 300, y: 70)); c.strokePath()
        }
        let r = FaceEngine.read(in: bmp, wallL: 64)
        #expect(r.seams.isEmpty)
        #expect(r.floor != nil && r.top != nil)
        #expect(r.onTheWall(CGPoint(x: 0.5, y: 0.5), width: 300, height: 400))
        #expect(!r.onTheWall(CGPoint(x: 0.5, y: 0.95), width: 300, height: 400))
        #expect(!r.onTheWall(CGPoint(x: 0.5, y: 0.05), width: 300, height: 400))
    }

    @Test func holdsOffTheWallAreDropped() throws {
        let bmp = canvas { c in
            c.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 350)); c.addLine(to: CGPoint(x: 300, y: 340)); c.strokePath()
        }
        let r = FaceEngine.read(in: bmp, wallL: 64)
        func hold(_ x: Double, _ y: Double) -> RouteScanner.Hold {
            RouteScanner.Hold(rect: CGRect(x: x - 0.02, y: y - 0.02, width: 0.04, height: 0.04), area: 0.001)
        }
        let s = RouteScanner.Swatch(hex: "#FF0000", lab: Lab(r: 255, g: 0, b: 0),
                                    holds: [hold(0.3, 0.3), hold(0.5, 0.5), hold(0.6, 0.7), hold(0.7, 0.95)], score: 1)
        let kept = RouteScanner.onTheWall([s], reading: r, width: 300, height: 400)
        #expect(kept.first?.holds.count == 3)
        // A colour that was only on the mat is not a route.
        let mat = RouteScanner.Swatch(hex: "#0000FF", lab: Lab(r: 0, g: 0, b: 255),
                                      holds: [hold(0.2, 0.93), hold(0.5, 0.95), hold(0.8, 0.97)], score: 1)
        #expect(RouteScanner.onTheWall([mat], reading: r, width: 300, height: 400).isEmpty)
    }

    /// The real walls keep every route after the mat and the top are read.
    @Test func realRoutesStayOnTheWall() throws {
        for name in ["gymwall", "wall2", "wall3", "wall4"] {
            let url = try #require(Bundle(for: FaceToken.self).url(forResource: name, withExtension: "jpg"))
            let image = try #require(UIImage(data: Data(contentsOf: url))?.cgImage)
            let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.workingWidth))
            let before = RouteScanner.palette(in: image)
            let after = RouteScanner.onTheWall(before, reading: FaceEngine.read(in: bmp), width: bmp.width, height: bmp.height)
            #expect(after.count >= before.count - 1, "\(name): \(before.count) -> \(after.count)")
            let lost = zip(before, after).map { $0.holds.count - $1.holds.count }.reduce(0, +)
            #expect(lost <= before.reduce(0) { $0 + $1.holds.count } / 5, "\(name) lost \(lost)")
        }
    }
}

/// The top of the wall counts only where its edge was seen.
@Suite("Top edge extent")
struct TopExtentTests {
    @Test func theTopStopsWhereTheEdgeStops() {
        // A horizontal line at y = 100 of 400, seen across the left half.
        let top = FaceEngine.Line(theta: .pi / 2, rho: 100, support: 1, run: 0...150)
        let r = FaceEngine.Reading(seams: [], floor: nil, top: top)
        #expect(!r.onTheWall(CGPoint(x: 0.25, y: 0.1), width: 300, height: 400))   // above the edge, under it
        #expect(r.onTheWall(CGPoint(x: 0.25, y: 0.5), width: 300, height: 400))
        #expect(r.onTheWall(CGPoint(x: 0.9, y: 0.1), width: 300, height: 400))     // past the edge: wall carries on
        let whole = FaceEngine.Line(theta: .pi / 2, rho: 100, support: 1)
        #expect(!FaceEngine.Reading(seams: [], floor: nil, top: whole).onTheWall(CGPoint(x: 0.9, y: 0.1), width: 300, height: 400))
    }
}
