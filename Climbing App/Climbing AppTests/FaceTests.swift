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
