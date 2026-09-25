import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Cuts the app's assets out of the supplied logo artwork.
//
// The source is one square image: the climber with the skeleton drawn over her,
// a wall beside her, and the wordmark underneath. An app icon cannot carry the
// wordmark, because at the size an icon is actually seen the word is a smudge
// and the name is already written under the icon by iOS. So the icon is the
// figure alone, and the full lockup is kept separately for the screens that
// have room for it.
//
// Nothing here is redrawn. The bounds are measured off the pixels so that a new
// version of the artwork can be dropped in and this rerun.

let source = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "logo-source.png"
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("could not read \(source)")
}
let w = img.width, h = img.height

var data = [UInt8](repeating: 0, count: w * h * 4)
let probe = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
probe.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

/// Row 0 is the top. CGContext bitmaps put row 0 at the top of the buffer.
func px(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let i = (y * w + x) * 4
    return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
}
let paper = px(4, 4)
func isInk(_ x: Int, _ y: Int) -> Bool {
    let p = px(x, y)
    return (paper.r - p.r) + (paper.g - p.g) > 60
}

// The wordmark is the only ink on the left of the lower third: below the
// figure's hips she is entirely on the right of the frame.
let leftEdge = w / 4, leftLimit = Int(Double(w) * 0.42)
var wordTop = h
for y in (h * 2 / 3)..<h {
    var n = 0
    for x in leftEdge..<leftLimit where isInk(x, y) { n += 1 }
    if n > 10 { wordTop = y; break }
}

// The leftmost ink anywhere, wordmark included. The clean paper the icon sits
// on is taken from the margin outside this; measuring it against the figure
// alone once pulled the wordmark's T into the patch and stretched a blue smear
// across the whole icon.
var inkLeft = w
for y in 0..<h {
    for x in 0..<inkLeft where isInk(x, y) { inkLeft = min(inkLeft, x) }
}

// The figure, above the wordmark.
var top = h, bottom = 0, left = w, right = 0
for y in 0..<max(0, wordTop - 6) {
    for x in 0..<w where isInk(x, y) {
        top = min(top, y); bottom = max(bottom, y)
        left = min(left, x); right = max(right, x)
    }
}
print("wordmark from row \(wordTop); figure rows \(top)...\(bottom) cols \(left)...\(right)")
print("clean paper margin: x < \(inkLeft)")

/// Which set in the catalog each file belongs to.
///
/// They used to be written loose at the top of the catalog and moved in by
/// hand, which means a rerun of this tool silently changes nothing until
/// somebody remembers to move four files.
let sets = [
    "icon-1024.png": "AppIcon.appiconset",
    "mark.png": "TraceMark.imageset",
    "lockup.png": "TraceLockup.imageset",
    "wordmark.png": "TraceWordmark.imageset"
]

func write(_ image: CGImage, _ name: String) {
    var dir = URL(fileURLWithPath: outDir)
    if let set = sets[name] {
        dir = dir.appendingPathComponent(set)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let contents = dir.appendingPathComponent("Contents.json")
        if !FileManager.default.fileExists(atPath: contents.path) {
            let json = """
            {
              "images" : [
                { "filename" : "\(name)", "idiom" : "universal", "scale" : "1x" },
                { "idiom" : "universal", "scale" : "2x" },
                { "idiom" : "universal", "scale" : "3x" }
              ],
              "info" : { "author" : "xcode", "version" : 1 }
            }
            """
            try? json.write(to: contents, atomically: true, encoding: .utf8)
        }
    }
    let url = dir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(sets[name] ?? "")/\(url.lastPathComponent)")
}

/// The ink, lifted off the paper it was printed on.
///
/// Cropping a rectangle of artwork and pasting it onto a flat color leaves a
/// visible box, because the paper in the artwork is a photographed texture and
/// a single sampled color is not. So the ink is matted instead: each pixel's
/// distance from the paper tone becomes its alpha, which gives the stipple and
/// the rough edges of the print partial coverage rather than a hard cutout, and
/// keeps every one of the ink's own colors.
let mattePaper = 30.0      // fully transparent at or below this distance
let matteInk = 150.0       // fully opaque at or above it

/// `keep` is asked about each source pixel, in source coordinates. Anything it
/// refuses comes out fully transparent, which is how the wordmark drops the
/// wall it overlaps without cropping the top off its own T.
func matted(x0: Int, y0: Int, width cw: Int, height ch: Int,
            keep: (Int, Int) -> Bool = { _, _ in true }) -> CGImage {
    var out = [UInt8](repeating: 0, count: cw * ch * 4)
    for y in 0..<ch {
        for x in 0..<cw {
            let p = px(x0 + x, y0 + y)
            let distance = Double((paper.r - p.r) + (paper.g - p.g)) / 2
            var a = min(max((distance - mattePaper) / (matteInk - mattePaper), 0), 1)
            if !keep(x0 + x, y0 + y) { a = 0 }
            let i = (y * cw + x) * 4
            // Premultiplied, which is what the bitmap layout below expects.
            out[i]     = UInt8(Double(p.r) * a)
            out[i + 1] = UInt8(Double(p.g) * a)
            out[i + 2] = UInt8(Double(p.b) * a)
            out[i + 3] = UInt8(a * 255)
        }
    }
    let ctx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8,
                        bytesPerRow: cw * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

/// A clean stretch of the artwork's own paper, for the icon to sit on.
///
/// Taken from the left margin, which no ink reaches, and stretched over the
/// square. It is the same paper at the same tone, so there is no edge anywhere.
func paperFill(_ ctx: CGContext, side: Int) {
    let patch = CGRect(x: 8, y: 8, width: max(8, inkLeft - 30), height: h - 16)
    if let clean = img.cropping(to: patch) {
        ctx.interpolationQuality = .high
        ctx.draw(clean, in: CGRect(x: 0, y: 0, width: side, height: side))
    } else {
        ctx.setFillColor(CGColor(red: CGFloat(paper.r) / 255, green: CGFloat(paper.g) / 255,
                                 blue: CGFloat(paper.b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
}

/// The figure on a square of its own paper.
///
/// `margin` is the share of the square left empty. iOS rounds the corners off
/// an icon, so the artwork has to sit well inside them.
func square(side: Int, margin: Double, alpha: Bool, name: String) {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue
                     : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: info)!
    if !alpha { paperFill(ctx, side: side) }
    ctx.interpolationQuality = .high

    let cropW = right - left + 1, cropH = bottom - top + 1
    let figure = matted(x0: left, y0: top, width: cropW, height: cropH)

    let box = Double(side) * (1 - margin * 2)
    let scale = min(box / Double(cropW), box / Double(cropH))
    let dw = Double(cropW) * scale, dh = Double(cropH) * scale
    ctx.draw(figure, in: CGRect(x: (Double(side) - dw) / 2, y: (Double(side) - dh) / 2,
                                width: dw, height: dh))
    write(ctx.makeImage()!, name)
}

// The icon: opaque, because an app icon may not carry an alpha channel.
square(side: 1024, margin: 0.10, alpha: false, name: "icon-1024.png")
// The mark on its own, transparent, for use inside the app.
square(side: 1024, margin: 0.02, alpha: true, name: "mark.png")

/// The whole lockup, mark and word together, matted off its paper.
///
/// Inside the app it sits on the app's own white, so carrying the artwork's
/// cream with it draws a visible square around the logo on every screen it
/// appears on.
func lockup(name: String) {
    var lTop = h, lBottom = 0, lLeft = w, lRight = 0
    for y in 0..<h {
        for x in 0..<w where isInk(x, y) {
            lTop = min(lTop, y); lBottom = max(lBottom, y)
            lLeft = min(lLeft, x); lRight = max(lRight, x)
        }
    }
    let pad = 12
    let x0 = max(0, lLeft - pad), y0 = max(0, lTop - pad)
    let cw = min(w - x0, lRight - lLeft + 1 + pad * 2)
    let ch = min(h - y0, lBottom - lTop + 1 + pad * 2)
    print("lockup rows \(lTop)...\(lBottom) cols \(lLeft)...\(lRight)")
    write(matted(x0: x0, y0: y0, width: cw, height: ch), name)
}

lockup(name: "lockup.png")

/// The word on its own, for the masthead.
///
/// Home used to set the name in the system serif beside the mark: the same word
/// in two different letterforms, six points apart. This is the word as it was
/// actually drawn.
///
/// Cutting it out means separating it from the wall, and the two overlap
/// vertically: the wall's bottom tail runs down past the top of the T. What
/// separates them is that in those rows the word is entirely on the left of the
/// frame and the wall entirely on the right. So the row where the word's second
/// letter starts is found, and above that row everything on the right is
/// dropped. Nothing here is a fixed number measured by eye.
func wordmark(name: String) {
    let bodyLeft = Int(Double(w) * 0.44)
    let bodyRight = Int(Double(w) * 0.55)
    var bodyTop = h
    for y in wordTop..<h {
        if (bodyLeft..<bodyRight).contains(where: { isInk($0, y) }) { bodyTop = y; break }
    }
    func keep(_ x: Int, _ y: Int) -> Bool { y >= bodyTop || x < bodyLeft }

    var top = h, bottom = 0, left = w, right = 0
    for y in wordTop..<h {
        for x in 0..<w where isInk(x, y) && keep(x, y) {
            top = min(top, y); bottom = max(bottom, y)
            left = min(left, x); right = max(right, x)
        }
    }
    guard top < bottom, left < right else { fatalError("no wordmark found") }

    let pad = 10
    let x0 = max(0, left - pad), y0 = max(0, top - pad)
    let cw = min(w - x0, right - left + 1 + pad * 2)
    let ch = min(h - y0, bottom - top + 1 + pad * 2)
    print("wordmark body from row \(bodyTop); rows \(top)...\(bottom) cols \(left)...\(right)")
    write(matted(x0: x0, y0: y0, width: cw, height: ch, keep: keep), name)
}

wordmark(name: "wordmark.png")
