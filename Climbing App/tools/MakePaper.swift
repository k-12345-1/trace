import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// A tileable square of the logo artwork's own paper.
//
// The app's ground is this paper, so the grain under it should be the same
// grain, not a noise function that happens to look similar. It is taken from
// the clean left margin of the artwork and made to tile by mirroring: a grain
// this fine has no direction, so a mirrored join is invisible while a straight
// join would show as a grid.

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "logo-source.png") as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!

let side = 128
let patch = img.cropping(to: CGRect(x: 30, y: 200, width: side, height: side))!

let out = side * 2
let ctx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Four copies, each mirrored into place, so every edge meets its own reflection.
for (i, j) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(i) * CGFloat(side), y: CGFloat(j) * CGFloat(side))
    if i == 1 { ctx.translateBy(x: CGFloat(side), y: 0); ctx.scaleBy(x: -1, y: 1) }
    if j == 1 { ctx.translateBy(x: 0, y: CGFloat(side)); ctx.scaleBy(x: 1, y: -1) }
    ctx.draw(patch, in: CGRect(x: 0, y: 0, width: side, height: side))
    ctx.restoreGState()
}

let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "paper.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.lastPathComponent) at \(out)x\(out)")
