import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Trace's mark, drawn once here and mirrored by MountainMark.swift in the app.
//
// An engraving rather than a logo: a ridge in outline with the light flank left
// bare and the shaded flank hatched in fine parallel strokes, the way a wood
// block print shades a mountain. Blue on white, because that is the pairing the
// app is built in and an icon that inverts the app is an icon for a different
// app.

let side: CGFloat = 1024
let blue = CGColor(red: 0x0F/255, green: 0x2C/255, blue: 0x5C/255, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

// The design space is 100 x 100, y downward.
let ridge: [CGPoint] = [
    CGPoint(x: 5,  y: 84),
    CGPoint(x: 22, y: 57),
    CGPoint(x: 31, y: 65),
    CGPoint(x: 46, y: 31),
    CGPoint(x: 54, y: 43),
    CGPoint(x: 63, y: 14),
    CGPoint(x: 95, y: 84)
]

/// The shaded flank: everything right of the summit.
let summitIndex = 5

func makeIcon(scale: CGFloat, inset: CGFloat, fileName: String) {
    let ctx = CGContext(data: nil, width: Int(side), height: Int(side),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

    ctx.setFillColor(white)
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

    // Design space to pixels, flipping y so the design reads top-down.
    let s = (side * (1 - inset * 2)) / 100
    let ox = (side - 100 * s) / 2
    let oy = (side - 100 * s) / 2
    func p(_ q: CGPoint) -> CGPoint {
        CGPoint(x: ox + q.x * s, y: side - (oy + q.y * s))
    }

    let body = CGMutablePath()
    body.move(to: p(ridge[0]))
    for q in ridge.dropFirst() { body.addLine(to: p(q)) }
    body.closeSubpath()

    // Hatching on the shaded flank, parallel to it, thinning as it descends.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    let a = ridge[summitIndex], b = ridge[6]
    let dx = b.x - a.x, dy = b.y - a.y
    let len = (dx * dx + dy * dy).squareRoot()
    let ux = dx / len, uy = dy / len          // along the flank
    let nx = -uy, ny = ux                     // across it, pointing into the body

    // Hachures: short strokes running across the shaded flank, from the ridge
    // inward, shortening as the flank falls away. This is the classical way a
    // printed map or a wood block shades a slope, and unlike lines drawn along
    // the flank it needs no clip edge to stop it, so nothing ends in a cut.
    ctx.setStrokeColor(blue)
    ctx.setLineCap(.round)

    let count = 26
    for i in 1..<count {
        let t = CGFloat(i) / CGFloat(count)
        let root = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
        // Long near the summit, short near the foot, with a little swell in
        // the middle so the edge of the shading is not a straight line.
        let swell = sin(Double(t) * Double.pi)
        let length = (20.0 * (1 - t) + 4.0) * (0.75 + 0.35 * swell)
        let tip = CGPoint(x: root.x + nx * length, y: root.y + ny * length)
        ctx.setLineWidth((1.9 - 0.9 * t) * s)
        ctx.move(to: p(root))
        ctx.addLine(to: p(tip))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // The ridge itself, over the hatching.
    ctx.setStrokeColor(blue)
    ctx.setLineWidth(4.4 * s)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(body)
    ctx.strokePath()

    guard let image = ctx.makeImage() else { fatalError("no image") }
    let url = URL(fileURLWithPath: fileName)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("no destination") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(fileName)")
}

makeIcon(scale: 1, inset: 0.12, fileName: CommandLine.arguments.count > 1
         ? CommandLine.arguments[1] : "icon-1024.png")
