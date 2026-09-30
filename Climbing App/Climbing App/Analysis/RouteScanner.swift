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
        return (holds(in: bmp, target: target, tolerance: tolerance), hex)
    }

    /// The same, from a color rather than from a point on the screen. This is
    /// what a tap on a chip runs when the wall's other colors are not to hand.
    static func detectHolds(in image: CGImage, color: Lab,
                            tolerance: Double = 30) -> [Hold] {
        guard let bmp = Bitmap(image, targetWidth: workingWidth) else { return [] }
        return holds(in: bmp, target: color, tolerance: tolerance)
    }

    /// Every blob close enough to one color to be a hold of it.
    static func holds(in bmp: Bitmap, target: Lab, tolerance: Double) -> [Hold] {
        var mask = [Bool](repeating: false, count: bmp.width * bmp.height)
        for i in 0..<(bmp.width * bmp.height) {
            mask[i] = bmp.lab(at: i).distance(to: target) < tolerance
        }
        return holds(in: bmp, mask: &mask)
    }

    /// The hold shaped things in a mask. A wall, a mat or a floor is one
    /// enormous blob and fails the size filter, which is why no color has to be
    /// excluded by name.
    /// Every blob in a mask with its shape statistics, whether or not it passed.
    /// For looking at what the filters are throwing away.
    struct Blob {
        var rect: CGRect
        var area: Double
        var fill: Double
        var aspect: Double
        var passed: Bool
    }

    static func blobs(in bmp: Bitmap, mask: inout [Bool]) -> [Blob] {
        let total = Double(bmp.width * bmp.height)
        let minPixels = Int(total * minAreaFraction)
        let maxPixels = Int(total * maxAreaFraction)
        var out: [Blob] = []
        for c in components(mask: &mask, width: bmp.width, height: bmp.height,
                            minPixels: max(minPixels, 8), maxPixels: Int(total)) {
            let w = Double(c.maxX - c.minX + 1), h = Double(c.maxY - c.minY + 1)
            let fill = Double(c.count) / (w * h)
            let aspect = max(w / h, h / w)
            out.append(Blob(
                rect: CGRect(x: Double(c.minX) / Double(bmp.width),
                             y: Double(c.minY) / Double(bmp.height),
                             width: w / Double(bmp.width), height: h / Double(bmp.height)),
                area: Double(c.count) / total,
                fill: fill, aspect: aspect,
                passed: w > 2 && h > 2 && fill > 0.32 && aspect < 5.5 && c.count <= maxPixels))
        }
        return out.sorted { $0.area > $1.area }
    }

    static func holds(in bmp: Bitmap, mask: inout [Bool]) -> [Hold] {
        let total = Double(bmp.width * bmp.height)
        let minPixels = Int(total * minAreaFraction)
        let maxPixels = Int(total * maxAreaFraction)

        var found: [Hold] = []
        for component in components(mask: &mask, width: bmp.width, height: bmp.height,
                                    minPixels: max(minPixels, 8), maxPixels: maxPixels) {
            let w = Double(component.maxX - component.minX + 1)
            let h = Double(component.maxY - component.minY + 1)
            guard w > 2, h > 2 else { continue }

            // Reject stringy shapes: floor seams, tape lines, wall edges.
            let fill = Double(component.count) / (w * h)
            let aspect = max(w / h, h / w)
            guard fill > 0.32, aspect < 5.5 else { continue }

            found.append(Hold(
                rect: CGRect(x: Double(component.minX) / Double(bmp.width),
                             y: Double(component.minY) / Double(bmp.height),
                             width: w / Double(bmp.width),
                             height: h / Double(bmp.height)),
                area: Double(component.count) / total
            ))
        }
        // Biggest first, so the review list leads with the holds that matter.
        return found.sorted { $0.area > $1.area }
    }

    // MARK: Reading the wall's colors

    /// One color on the wall, and the route it picks out.
    struct Swatch: Identifiable, Equatable {
        var id = UUID()
        /// For drawing the chip.
        var hex: String
        /// The color itself, for finding these holds again at full resolution.
        var lab: Lab
        /// The route, found when the wall was read. This is what gets drawn:
        /// there is no second pass to disagree with it.
        var holds: [Hold]
        /// How much this color looks like a route rather than like scenery.
        var score: Double

        static func == (a: Swatch, b: Swatch) -> Bool { a.id == b.id }
    }

    /// Reading the whole wall happens at the same resolution as everything
    /// else.
    ///
    /// It used to be coarser, on the reasoning that counting holds needs less
    /// detail than drawing boxes round them. On a real photograph the two
    /// resolutions disagree: blobs that merge at two hundred and forty split at
    /// four hundred and twenty, so a chip said twelve and five boxes appeared.
    /// One pass, one answer, and choosing a colour is now instant because the
    /// holds were found when the wall was read.
    static let paletteWidth = workingWidth
    /// Fewer blobs than this is not a route, it is three holds that happen to
    /// match, or a logo on the mat.
    static let minimumHolds = 3

    /// Every route color Trace can see on this wall, best first.
    ///
    /// This is the way round that matches how a gym works. Routes are set in a
    /// color, the colors are the first thing you see standing at the bottom of
    /// the wall, and asking somebody to tap one hold precisely enough to sample
    /// it, then work a tolerance slider when the tap landed on a shadow, is
    /// asking them to do the computer's job. Trace reads the colors itself and
    /// offers them.
    ///
    /// The wall does not have to be excluded by hand. Wall, mats and floor are
    /// the most common colors in any photograph of a wall, and they come out as
    /// single enormous blobs, which the size filter throws away: a color that
    /// leaves nothing hold shaped behind leaves no swatch.
    static func palette(in image: CGImage, tolerance: Double = 30,
                        limit: Int = 10) -> [Swatch] {
        guard let bmp = Bitmap(image, targetWidth: paletteWidth) else { return [] }

        // What the wall is made of, taken out first.
        //
        // Ranking colours by how many pixels they cover finds the wall, the
        // mats, the ceiling and the shadows, every time, because that is what a
        // photograph of a wall is mostly made of. On a flat synthetic wall that
        // did no harm: one colour, one enormous blob, thrown out by the size
        // filter. A real wall is textured, lit unevenly and full of seams, bolt
        // holes and trusses, so it breaks into thousands of small blobs that
        // are exactly hold shaped, and the scan comes back with six shades of
        // grey and no routes.
        let ground = groundColors(in: bmp)
        // A grey that is not quite the wall's grey is still the wall: a shadow,
        // a seam, a panel in different light. Neutral candidates have to stand
        // well clear of every ground colour or they are dropped, which is what
        // keeps a route of white holds and loses the 41 boxes of panel shade
        // that led the list once shading was allowed for.
        let candidates = commonColors(in: bmp, apart: tolerance * 0.6, ground: ground)
            .filter { c in
                let chroma = (c.lab.a * c.lab.a + c.lab.b * c.lab.b).squareRoot()
                guard chroma < groundChroma else { return true }
                let nearest = ground.map { $0.distance(to: c.lab) }.min() ?? .infinity
                return nearest >= neutralClearance
            }
        var labels = segment(bmp, colors: candidates.map(\.lab), tolerance: tolerance,
                             ground: ground)
        var swatches: [Swatch] = []
        for (i, candidate) in candidates.enumerated() {
            let found = holds(in: bmp, labels: &labels, index: i)
            guard found.count >= minimumHolds else { continue }
            swatches.append(Swatch(hex: candidate.hex, lab: candidate.lab,
                                   holds: found,
                                   score: score(found)
                                        * distinctness(candidate.lab, from: ground)))
        }
        return Array(swatches.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Every blob of one color, where a pixel belongs to whichever of the
    /// wall's colors is nearest to it.
    ///
    /// A plain distance mask cannot separate a red route from an orange one:
    /// widen it enough to find the shaded side of a red hold and it has taken
    /// in the orange route too. Letting every pixel go to its nearest color
    /// instead means the two routes divide the wall between them, which is what
    /// the eye does standing in front of it.
    static func holds(in bmp: Bitmap, colors: [Lab], index: Int,
                      tolerance: Double) -> [Hold] {
        guard colors.indices.contains(index) else { return [] }
        var labels = segment(bmp, colors: colors, tolerance: tolerance,
                             ground: groundColors(in: bmp))
        return holds(in: bmp, labels: &labels, index: index)
    }

    // MARK: What the wall is made of

    /// How close to a wall colour a pixel has to be before it is wall.
    ///
    /// Tight on purpose. A white hold on a grey wall and a cream hold on a
    /// concrete panel are both real routes, and a generous reach around the
    /// wall's own grey swallows them.
    static let groundReach = 13.0
    /// A colour covering this much of the photograph is scenery, not a route.
    ///
    /// The separation is not close. On a real wall the panels, the ceiling, the
    /// mats and the shadowed overhang each run from a few per cent of the
    /// picture into the tens, while the busiest route colour on a wall covered
    /// in holds came to a little over half of one per cent. Two per cent sits
    /// in the gap with room on both sides.
    ///
    /// This replaced a rule that took the most common colours until they
    /// covered some share of the picture, which is the same thing said in a way
    /// that breaks: on a wall with less scenery in the frame, the running total
    /// keeps going and eats the route.
    static let groundShare = 0.02
    static let groundLimit = 12

    /// Below this chroma a colour is a grey, a beige or a shadow: the stuff
    /// walls, mats and ceilings are made of. Above it, covering a lot of the
    /// picture is not enough on its own to be called scenery.
    static let groundChroma = 16.0
    /// How far a neutral colour has to sit from the wall's own colours before
    /// it can be a route rather than a shade of the wall.
    static let neutralClearance = 25.0

    /// The colours of the wall, the mats, the ceiling and the shadows.
    ///
    /// Share alone was the rule, and on the second real wall it threw the
    /// routes away: a blue route with two big volumes covered 2.2% of the
    /// photograph and a yellow one 2.4%, both past the line, and both were
    /// removed as scenery before the palette was read. So a colour past the
    /// line is scenery if it is grey enough to be a wall, or if it comes as a
    /// sheet: its biggest piece is bigger than any hold could be. A blue route
    /// is neither, whatever it covers.
    static func groundColors(in bmp: Bitmap) -> [Lab] {
        let total = Double(bmp.width * bmp.height)
        return commonColors(in: bmp, step: 12, keep: groundLimit, apart: groundReach)
            .filter { Double($0.count) / total >= groundShare }
            .filter { isScenery($0.lab, in: bmp) }
            .map(\.lab)
    }

    static func isScenery(_ lab: Lab, in bmp: Bitmap) -> Bool {
        if (lab.a * lab.a + lab.b * lab.b).squareRoot() < groundChroma { return true }
        let total = bmp.width * bmp.height
        var mask = [Bool](repeating: false, count: total)
        for i in 0..<total { mask[i] = bmp.lab(at: i).distance(to: lab) < groundReach }
        let biggest = components(mask: &mask, width: bmp.width, height: bmp.height,
                                 minPixels: 8, maxPixels: total).map(\.count).max() ?? 0
        return Double(biggest) / Double(total) > maxAreaFraction
    }

    static func isGround(_ lab: Lab, _ ground: [Lab]) -> Bool {
        ground.contains { $0.distance(to: lab) < groundReach }
    }

    /// Which of the wall's colors each pixel belongs to, or -1 for none of them.
    ///
    /// Done once for the whole palette rather than once per color. The naive
    /// version rebuilt this for every candidate, which is the same work
    /// fourteen times over and turns reading a wall from a moment into a wait.
    static func segment(_ bmp: Bitmap, colors: [Lab], tolerance: Double,
                        ground: [Lab] = []) -> [Int8] {
        var labels = [Int8](repeating: -1, count: bmp.width * bmp.height)
        guard !colors.isEmpty, colors.count < 127 else { return labels }
        for i in 0..<(bmp.width * bmp.height) {
            let lab = bmp.lab(at: i)
            // Wall is wall, however close it happens to sit to a route colour.
            if isGround(lab, ground) { continue }
            // A pixel with colour in it may be a shaded face of a hold, so
            // lightness counts for less. A grey pixel has no shaded face to be:
            // it is wall, and it has to match a candidate outright, and closely.
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            let shaded = chroma >= groundChroma
            var nearest: Int8 = -1
            var best = shaded ? tolerance : tolerance * 0.6
            for (j, color) in colors.enumerated() {
                let d = shaded ? lab.shadeDistance(to: color) : lab.distance(to: color)
                if d < best { best = d; nearest = Int8(j) }
            }
            labels[i] = nearest
        }
        return labels
    }

    static func holds(in bmp: Bitmap, labels: inout [Int8], index: Int) -> [Hold] {
        var mask = [Bool](repeating: false, count: labels.count)
        for i in labels.indices { mask[i] = labels[i] == Int8(index) }
        return holds(in: bmp, mask: &mask)
    }

    /// How much a set of blobs looks like a route.
    ///
    /// A route is several holds spread up the wall. Six holds from the floor to
    /// the top beats twenty scattered across one corner, which is a bank of
    /// volumes or a pattern in the flooring.
    static func score(_ holds: [Hold]) -> Double {
        guard !holds.isEmpty else { return 0 }
        let ys = holds.map { Double($0.rect.midY) }
        let spread = (ys.max() ?? 0) - (ys.min() ?? 0)
        return Double(min(holds.count, 25)) * (0.35 + spread)
    }

    /// How far a colour stands out from the wall it is on.
    ///
    /// Whatever scenery survives being called ground is, by construction, the
    /// stuff that sits closest to the wall's own colour: the ceiling a shade
    /// bluer than the panels, the seam a shade darker. A route is the opposite,
    /// and it is the opposite whether it stands out by hue or by lightness,
    /// which is why this measures distance from the wall rather than
    /// saturation. A white route on grey panels is as distinct as a yellow one,
    /// and a saturation rule would have thrown it away.
    static let distinctFull = 35.0

    static func distinctness(_ lab: Lab, from ground: [Lab]) -> Double {
        guard let nearest = ground.map({ $0.distance(to: lab) }).min() else { return 1 }
        return min(1, max(0.25, nearest / distinctFull))
    }

    struct Candidate {
        var lab: Lab
        var hex: String
        var count: Int
    }

    /// The colors a photograph is actually made of, coarsely.
    ///
    /// A histogram in Lab rather than clustering: k-means on a quarter of a
    /// million pixels is slower and no better at this, because the question is
    /// only "which colors are there enough of to be worth a mask".
    static func commonColors(in bmp: Bitmap, step: Double = 12,
                             keep: Int = 20, apart: Double = 18,
                             ground: [Lab] = []) -> [Candidate] {
        struct Bin { var l = 0.0, a = 0.0, b = 0.0, r = 0.0, g = 0.0, bl = 0.0, n = 0.0 }
        var bins: [Int: Bin] = [:]

        for i in 0..<(bmp.width * bmp.height) {
            let lab = bmp.lab(at: i)
            if isGround(lab, ground) { continue }
            let key = (Int(lab.l / step) &* 73856093)
                ^ (Int((lab.a + 128) / step) &* 19349663)
                ^ (Int((lab.b + 128) / step) &* 83492791)
            var bin = bins[key] ?? Bin()
            let rgb = bmp.rgb(at: i)
            bin.l += lab.l; bin.a += lab.a; bin.b += lab.b
            bin.r += Double(rgb.0); bin.g += Double(rgb.1); bin.bl += Double(rgb.2)
            bin.n += 1
            bins[key] = bin
        }

        // Bins are a grid laid over a continuous space, so one hold color
        // usually straddles several of them. Merged, largest first: a bin that
        // is not far enough from a color already accepted joins it rather than
        // becoming a rival for its own pixels.
        var merged: [Bin] = []
        for bin in bins.values.filter({ $0.n >= 12 }).sorted(by: { $0.n > $1.n }) {
            let lab = Lab(l: bin.l / bin.n, a: bin.a / bin.n, b: bin.b / bin.n)
            let near = merged.firstIndex {
                Lab(l: $0.l / $0.n, a: $0.a / $0.n, b: $0.b / $0.n).shadeDistance(to: lab) < apart
            }
            if let near {
                merged[near].l += bin.l; merged[near].a += bin.a; merged[near].b += bin.b
                merged[near].r += bin.r; merged[near].g += bin.g; merged[near].bl += bin.bl
                merged[near].n += bin.n
            } else if merged.count < keep {
                merged.append(bin)
            }
        }

        return merged.map { bin in
            Candidate(lab: Lab(l: bin.l / bin.n, a: bin.a / bin.n, b: bin.b / bin.n),
                      hex: String(format: "#%02X%02X%02X",
                                  Int((bin.r / bin.n).rounded()),
                                  Int((bin.g / bin.n).rounded()),
                                  Int((bin.bl / bin.n).rounded())),
                      count: Int(bin.n))
        }
    }

    // MARK: One hold, tapped

    /// The hold under a finger.
    ///
    /// Colour segmentation misses holds: one in shadow, one half behind a
    /// volume, one whose plastic is a shade off the rest of the set. The answer
    /// is not a tolerance slider, which asks the climber to solve a colour
    /// science problem to get their own route back. It is to let them point at
    /// the hold that was missed.
    ///
    /// This grows a blob out from the tapped pixel rather than dropping a fixed
    /// square there, so a hold added by hand has the same outline as a hold
    /// found by the scan and can be told apart from its neighbours.
    ///
    /// Nil when the tap grew into something that is not a hold: the wall, a
    /// mat, the whole panel. The caller puts a plain box there instead, because
    /// a tap that does nothing is indistinguishable from a tap that missed.
    static func hold(in image: CGImage, at point: CGPoint,
                     tolerance: Double = 34) -> Hold? {
        guard let bmp = Bitmap(image, targetWidth: workingWidth) else { return nil }
        let x = min(max(Int((Double(bmp.width) * point.x).rounded()), 0), bmp.width - 1)
        let y = min(max(Int((Double(bmp.height) * point.y).rounded()), 0), bmp.height - 1)

        let target = bmp.averageLab(around: (x, y), radius: 2)
        var mask = [Bool](repeating: false, count: bmp.width * bmp.height)
        for i in 0..<(bmp.width * bmp.height) {
            mask[i] = bmp.lab(at: i).distance(to: target) < tolerance
        }

        let start = y * bmp.width + x
        guard mask[start] else { return nil }

        var comp = Component()
        var stack = [start]
        mask[start] = false
        while let i = stack.popLast() {
            let px = i % bmp.width, py = i / bmp.width
            comp.add(px, py)
            if px > 0, mask[i - 1] { mask[i - 1] = false; stack.append(i - 1) }
            if px < bmp.width - 1, mask[i + 1] { mask[i + 1] = false; stack.append(i + 1) }
            if py > 0, mask[i - bmp.width] { mask[i - bmp.width] = false; stack.append(i - bmp.width) }
            if py < bmp.height - 1, mask[i + bmp.width] {
                mask[i + bmp.width] = false; stack.append(i + bmp.width)
            }
        }

        let total = Double(bmp.width * bmp.height)
        guard comp.count >= 6, Double(comp.count) / total <= maxAreaFraction else { return nil }

        let w = Double(comp.maxX - comp.minX + 1)
        let h = Double(comp.maxY - comp.minY + 1)
        return Hold(rect: CGRect(x: Double(comp.minX) / Double(bmp.width),
                                 y: Double(comp.minY) / Double(bmp.height),
                                 width: w / Double(bmp.width),
                                 height: h / Double(bmp.height)),
                    area: Double(comp.count) / total)
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

    func rgb(at index: Int) -> (UInt8, UInt8, UInt8) {
        let i = index * 4
        guard i + 2 < pixels.count else { return (136, 136, 136) }
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

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
    /// Distance with lightness counted at less than half weight.
    ///
    /// A hold is one colour lit from one side: its shaded face is the same
    /// plastic, darker. In plain Lab distance the dark side of a blue hold is
    /// nearer to a grey shadow than to the lit side of the same hold, so it was
    /// handed to the shadow and the hold came back as half a box. Down-weighting
    /// L is what says "same colour, less light".
    func shadeDistance(to other: Lab) -> Double {
        let dl = (l - other.l) * 0.4, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    func distance(to other: Lab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}
