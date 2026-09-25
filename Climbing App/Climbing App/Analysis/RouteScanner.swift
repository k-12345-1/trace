import Foundation
import CoreGraphics
import Vision
import ImageIO

/// Finds a route in a photo of a wall.
///
/// Gyms mark routes by hold color, so that is what this reads. You tap one hold,
/// and every hold close enough to it in color is picked out. That is the same
/// signal a climber uses standing at the bottom of the wall, and it needs no
/// trained model, no dataset and no gym partnership: it works on the first photo
/// in any gym on earth.
///
/// What it is not: it does not recognize hold *shapes*, and it cannot tell a route
/// apart from unrelated holds that happen to share its color. The review step
/// exists so the climber can throw those out.
enum RouteScanner {

    /// A detected hold, in normalized image coordinates with the origin top left.
    struct Hold: Identifiable, Hashable {
        var id = UUID()
        var rect: CGRect
        var area: Double
    }

    struct Result {
        var holds: [Hold]
        var colorHex: String
        /// Grades read off a route tag, most plausible first.
        var grades: [String]
    }

    // Tuning. A hold is a small fraction of a wall photo, and a blob that fills
    // half the frame is a mat or a wall panel, not a hold.
    static let minAreaFraction = 0.00025
    static let maxAreaFraction = 0.06
    /// Analysis resolution. Big enough to separate holds, small enough to be instant.
    static let workingWidth = 420

    // MARK: Color segmentation

    /// - Parameters:
    ///   - sample: the tapped point, normalized, origin top left.
    ///   - tolerance: CIE76 color distance. Around 20 is tight, 45 is generous.
    static func detectHolds(in image: CGImage,
                            sample: CGPoint,
                            tolerance: Double = 30) -> (holds: [Hold], colorHex: String) {
        guard let bmp = Bitmap(image, targetWidth: workingWidth) else { return ([], "#888888") }

        let sx = Int((Double(bmp.width) * sample.x).rounded())
        let sy = Int((Double(bmp.height) * sample.y).rounded())
        let target = bmp.averageLab(around: (sx, sy), radius: 2)
        let hex = bmp.hex(at: (min(max(sx, 0), bmp.width - 1), min(max(sy, 0), bmp.height - 1)))

        // Binary mask of everything close enough in color to what was tapped.
        var mask = [Bool](repeating: false, count: bmp.width * bmp.height)
        for i in 0..<(bmp.width * bmp.height) {
            mask[i] = bmp.lab(at: i).distance(to: target) < tolerance
        }

        let total = Double(bmp.width * bmp.height)
        let minPixels = Int(total * minAreaFraction)
        let maxPixels = Int(total * maxAreaFraction)

        var holds: [Hold] = []
        for component in components(mask: &mask, width: bmp.width, height: bmp.height,
                                    minPixels: max(minPixels, 8), maxPixels: maxPixels) {
            let w = Double(component.maxX - component.minX + 1)
            let h = Double(component.maxY - component.minY + 1)
            guard w > 2, h > 2 else { continue }

            // Reject stringy shapes: floor seams, tape lines, wall edges.
            let fill = Double(component.count) / (w * h)
            let aspect = max(w / h, h / w)
            guard fill > 0.32, aspect < 5.5 else { continue }

            holds.append(Hold(
                rect: CGRect(x: Double(component.minX) / Double(bmp.width),
                             y: Double(component.minY) / Double(bmp.height),
                             width: w / Double(bmp.width),
                             height: h / Double(bmp.height)),
                area: Double(component.count) / total
            ))
        }
        // Biggest first, so the review list leads with the holds that matter.
        return (holds.sorted { $0.area > $1.area }, hex)
    }

    // MARK: Connected components

    private struct Component {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var count = 0
        mutating func add(_ x: Int, _ y: Int) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            count += 1
        }
    }

    /// Flood fill with an explicit stack. Recursion would blow the stack on a
    /// large blob, and a wall photo has plenty of those.
    private static func components(mask: inout [Bool], width: Int, height: Int,
                                   minPixels: Int, maxPixels: Int) -> [Component] {
        var out: [Component] = []
        var stack: [Int] = []

        for start in 0..<(width * height) where mask[start] {
            var comp = Component()
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            mask[start] = false

            while let i = stack.popLast() {
                let x = i % width, y = i / width
                comp.add(x, y)
                if x > 0, mask[i - 1] { mask[i - 1] = false; stack.append(i - 1) }
                if x < width - 1, mask[i + 1] { mask[i + 1] = false; stack.append(i + 1) }
                if y > 0, mask[i - width] { mask[i - width] = false; stack.append(i - width) }
                if y < height - 1, mask[i + width] { mask[i + width] = false; stack.append(i + width) }
            }

            if comp.count >= minPixels && comp.count <= maxPixels { out.append(comp) }
        }
        return out
    }

    // MARK: Route tag

    // A trailing \b cannot follow an optional + or -, because those are not word
    // characters and so there is no boundary after them. The regex would quietly
    // drop the modifier and read 7a+ as 7a. A negative lookahead is what is wanted.
    private static let tail = "(?![A-Za-z0-9])"
    private static let gradePatterns = [
        "\\bV(?:B|[0-9]{1,2})[+-]?" + tail,          // Hueco, the bouldering default
        "\\b5\\.[0-9]{1,2}[a-dA-D]?[+-]?" + tail,    // Yosemite
        "\\b[4-9][abcABC]\\+?" + tail                // French and Font
    ]

    /// Reads the plastic tag beside a route. By far the cheapest way to know a
    /// grade: the gym already wrote it down.
    static func readGrades(in image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let strings = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: grades(in: strings))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: []) }
        }
    }

    static func grades(in strings: [String]) -> [String] {
        var found: [String] = []
        for s in strings {
            for pattern in gradePatterns {
                guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = s as NSString
                for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    let g = ns.substring(with: m.range).uppercased()
                    if !found.contains(g) { found.append(g) }
                }
            }
        }
        return found
    }
}

// MARK: - Pixels

/// A downscaled RGBA copy of an image, with color conversion cached in Lab.
struct Bitmap {
    let width: Int
    let height: Int
    private let pixels: [UInt8]
    private let labs: [Lab]

    init?(_ image: CGImage, targetWidth: Int) {
        let scale = min(1.0, Double(targetWidth) / Double(image.width))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buffer, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        width = w; height = h; pixels = buffer
        var converted = [Lab](repeating: Lab(l: 0, a: 0, b: 0), count: w * h)
        for i in 0..<(w * h) {
            converted[i] = Lab(r: buffer[i * 4], g: buffer[i * 4 + 1], b: buffer[i * 4 + 2])
        }
        labs = converted
    }

    func lab(at index: Int) -> Lab { labs[index] }

    func averageLab(around p: (Int, Int), radius: Int) -> Lab {
        var l = 0.0, a = 0.0, b = 0.0, n = 0.0
        for y in (p.1 - radius)...(p.1 + radius) {
            for x in (p.0 - radius)...(p.0 + radius) {
                guard x >= 0, y >= 0, x < width, y < height else { continue }
                let c = labs[y * width + x]
                l += c.l; a += c.a; b += c.b; n += 1
            }
        }
        guard n > 0 else { return Lab(l: 0, a: 0, b: 0) }
        return Lab(l: l / n, a: a / n, b: b / n)
    }

    func hex(at p: (Int, Int)) -> String {
        let i = (p.1 * width + p.0) * 4
        guard i + 2 < pixels.count else { return "#888888" }
        return String(format: "#%02X%02X%02X", pixels[i], pixels[i + 1], pixels[i + 2])
    }
}

/// CIE L*a*b*. Color distance in RGB does not match what the eye sees, and a
/// route is picked out by eye, so the comparison happens here instead.
struct Lab {
    var l: Double, a: Double, b: Double

    init(l: Double, a: Double, b: Double) { self.l = l; self.a = a; self.b = b }

    init(r: UInt8, g: UInt8, b bb: UInt8) {
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let rl = linear(r), gl = linear(g), bl = linear(bb)

        // sRGB to XYZ, D65.
        let x = (rl * 0.4124 + gl * 0.3576 + bl * 0.1805) / 0.95047
        let y = (rl * 0.2126 + gl * 0.7152 + bl * 0.0722)
        let z = (rl * 0.0193 + gl * 0.1192 + bl * 0.9505) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3) : (7.787 * t) + 16.0 / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        l = 116 * fy - 16
        a = 500 * (fx - fy)
        self.b = 200 * (fy - fz)
    }

    /// CIE76. Good enough to separate gym hold colors, and fast.
    func distance(to other: Lab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}
