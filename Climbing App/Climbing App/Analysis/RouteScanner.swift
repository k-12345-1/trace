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
        /// The hold's outline, normalised, as the convex hull of its pixels.
        /// Empty for a hold placed by hand with nothing under it.
        var outline: [CGPoint] = []
    }

    struct Result {
        var holds: [Hold]
        var colorHex: String
        /// Grades read off a route tag, most plausible first.
        var grades: [String]
    }

    // Tuning. A hold is a small fraction of a wall photo, and a blob that fills
    // half the frame is a mat or a wall panel, not a hold.
    static let minAreaFraction = 0.00015
    static let maxAreaFraction = 0.06
    /// Analysis resolution. Big enough to separate holds, small enough to be instant.
    static let workingWidth = 420
    /// What is hold shaped. A hold is a lump: it fills most of its box and is
    /// not much longer than it is wide. The shadow line down an arete is
    /// neither, and at five and a half to one it was passing as a hold and
    /// being made the first move of the route.
    static let holdAspect = 3.2
    static let holdFill = 0.36
    /// A curved hold, a crescent or a snake, fills little of its box and is
    /// still a hold. Below this aspect the box is compact enough that a thin
    /// fill is a bend rather than a line, and the fill rule is eased.
    static let curvedAspect = 2.0
    static let curvedFill = 0.22

    /// A blob this many pixels thick at working width is a hold whatever
    /// its outline, up to this aspect. The orange snakes on the first wall
    /// run about twelve wide; an arete's shadow runs two.
    static let thickHold = 7.0
    static let snakeAspect = 6.0

    static func isHoldShaped(fill: Double, aspect: Double) -> Bool {
        aspect < holdAspect && (fill > holdFill || (aspect < curvedAspect && fill > curvedFill))
    }

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
                passed: w > 2 && h > 2 && isHoldShaped(fill: fill, aspect: aspect) && c.count <= maxPixels))
        }
        return out.sorted { $0.area > $1.area }
    }

    /// - Parameters:
    ///   - labels: which candidate each pixel went to, for the patch rule.
    ///   - colors: the candidates, so the rule knows which labels are coloured
    ///     routes. The dark candidate claims the shadowed rim of every hold,
    ///     and counted as "another route" it made every hold a patch.
    static func holds(in bmp: Bitmap, mask: inout [Bool],
                      labels: [Int8]? = nil, index: Int = -1, colors: [Lab] = [],
                      ground: [Lab] = []) -> [Hold] {
        let wall = ground.isEmpty ? groundColors(in: bmp) : ground
        let isWall: (Int) -> Bool = { i in i < bmp.width * bmp.height && isGround(bmp.lab(at: i), wall) }
        let colored = colors.map { ($0.a * $0.a + $0.b * $0.b).squareRoot() >= groundChroma }
        // A dark candidate is black holds, and also every shadow a hold
        // throws and every piece of dark panel. Two more rules for it.
        let dark = colors.indices.contains(index) && colors[index].l < darkHold
        // Only a pale candidate can be a patch: chalk is white, and a cream
        // route is where chalk lands. A coloured hold's shaded rim can fall to
        // a candidate outside its hue family, and judged for enclosure every
        // yellow hold on the first wall became a patch on its own shadow.
        let pale = colors.indices.contains(index) && isPale(colors[index])
        let total = Double(bmp.width * bmp.height)
        let minPixels = Int(total * minAreaFraction)
        let maxPixels = Int(total * maxAreaFraction)

        // Chalk. A hold that has been climbed is white where hands went,
        // and read by colour that white is a hole in it or a bite out of
        // its edge. Any bright, colourless pixel not already another
        // route's is chalk a coloured hold can take back, below, when it
        // sits against it. Wall is not excluded here: once a white route
        // and its chalk cover enough of the picture white is called wall,
        // and the chalk on every hold with it. The size cap in adoptChalk
        // is what keeps a hold from flooding into a white panel.
        var chalk: [Bool] = []
        if colors.indices.contains(index), colored[index], let labels {
            chalk = [Bool](repeating: false, count: bmp.width * bmp.height)
            for i in chalk.indices {
                if bmp.isExcluded(i) { continue }
                let j = Int(labels[i])
                if j >= 0, colored.indices.contains(j), colored[j] { continue }
                chalk[i] = isChalk(bmp.lab(at: i))
            }
        }

        var blobs = components(mask: &mask, width: bmp.width, height: bmp.height,
                               minPixels: max(minPixels, 8), maxPixels: maxPixels,
                               outlines: true)
        if !chalk.isEmpty {
            // Chalk across the middle of a hold splits it into two blobs
            // of colour. Each takes the chalk it touches; put together
            // again they are one blob, and found again as one.
            var union = [Bool](repeating: false, count: bmp.width * bmp.height)
            for i in blobs.indices {
                adoptChalk(into: &blobs[i], chalk: &chalk, width: bmp.width, height: bmp.height)
                for p in blobs[i].pixels { union[Int(p)] = true }
            }
            blobs = components(mask: &union, width: bmp.width, height: bmp.height,
                               minPixels: max(minPixels, 8), maxPixels: maxPixels * 2,
                               outlines: true)
        }

        var found: [Hold] = []
        for var component in blobs {
            let w = Double(component.maxX - component.minX + 1)
            let h = Double(component.maxY - component.minY + 1)
            guard w > 2, h > 2 else { continue }

            // Reject stringy shapes: floor seams, tape lines, wall edges.
            // Unless the string is thick: a snake of a hold is as tall and
            // as thin in its box as a shadow line, and many pixels wide
            // where the shadow is one or two.
            let fill = Double(component.count) / (w * h)
            let aspect = max(w / h, h / w)
            let thick = component.thickness(width: bmp.width) >= thickHold && aspect < snakeAspect
            guard isHoldShaped(fill: fill, aspect: aspect) || thick else { continue }
            // And hollow ones: a ring of glare round a panel encloses a
            // hole. A snake of a hold does not, however little of its hull
            // it fills, and the orange route on the first wall is snakes.
            guard component.holeShare(width: bmp.width, isWall: isWall) < hollow,
                  component.hullFill(width: bmp.width) >= lumpFill else { continue }
            // And patches on another route's hold.
            // A white blob is held to a lower line: chalk on the lip of a
            // hold runs past the hold's edge, and the coloured hold has
            // already taken it in above.
            if pale, let labels, isPatch(component, labels: labels, index: index, colored: colored,
                                         width: bmp.width, height: bmp.height,
                                         share: isChalk(colors[index]) ? chalkPatchShare : patchShare) {
                continue
            }
            // A hold stands clear of the wall. A lit panel is wall that
            // has drifted a shade toward cream, a chalk streak is wall gone
            // a shade whiter, and either can read as a muted route's
            // colour blob by blob. Their pixels sit a little way from the
            // wall's colours; a hold's sit far. Not for a dark candidate,
            // whose black holds on a black panel are near the wall by
            // nature and are judged by shape above.
            if !dark, colors.indices.contains(index),
               clearance(of: component, in: bmp, wall: wallApart(from: colors[index], wall),
                         labels: labels, index: index) < holdClearance { continue }
            if dark {
                // A dark blob bigger than any black hold is a panel.
                guard Double(component.count) / total <= darkSheet else { continue }
                // And a dark blob with a coloured hold sitting on top of it
                // is that hold's shadow: light comes from above. A shadow
                // is a thin crescent; a black volume under a blue hold is a
                // hold, however much blue sits above it.
                let small = Double(component.count) / total <= shadowSize
                if small, let labels, isShadow(component, labels: labels, colored: colored, width: bmp.width) { continue }
                // And a dark blob that is wall in shade: the wedge under a
                // ceiling beam, the seam down a panel's edge. Neutral,
                // clearly lighter than the black route that claimed it,
                // and still darker than the wall it lies on.
                if isShade(component, in: bmp, route: colors[index], wall: wall) { continue }
            }

            found.append(Hold(
                rect: CGRect(x: Double(component.minX) / Double(bmp.width),
                             y: Double(component.minY) / Double(bmp.height),
                             width: w / Double(bmp.width),
                             height: h / Double(bmp.height)),
                area: Double(component.count) / total,
                outline: component.outline(width: bmp.width, height: bmp.height)
            ))
        }
        // Biggest first, so the review list leads with the holds that matter.
        return found.sorted { $0.area > $1.area }
    }

    /// How far, in Lab, a hold's own pixels sit from the wall on median.
    /// The lit panel on the fifth wall sat at 18.4 and the chalk streak
    /// on it at 15.4; the cream volumes on that wall at 31 and more.
    static let holdClearance = 22.0

    /// The wall colours that are not the candidate's own. A white route
    /// on a wall where white has been called scenery would otherwise be
    /// judged against itself and lose every hold.
    private static func wallApart(from color: Lab, _ wall: [Lab]) -> [Lab] {
        wall.filter { $0.distance(to: color) >= groundReach }
    }

    /// The median distance of a blob's pixels from the nearest wall colour,
    /// over a sample of them. Only the blob's own pixels, the ones the
    /// segmentation gave this candidate: adopted chalk is far from a grey
    /// wall by nature, and counted it carried the lit panel on the fifth
    /// wall, with the pale fringe it had taken, past the line.
    private static func clearance(of component: Component, in bmp: Bitmap, wall: [Lab],
                                  labels: [Int8]? = nil, index: Int = -1) -> Double {
        guard !wall.isEmpty, !component.pixels.isEmpty else { return .infinity }
        let step = max(1, component.pixels.count / 400)
        var ds: [Double] = []
        var i = 0
        while i < component.pixels.count {
            let p = Int(component.pixels[i])
            i += step
            if let labels, labels[p] != Int8(index) { continue }
            let lab = bmp.lab(at: p)
            ds.append(wall.map { $0.distance(to: lab) }.min() ?? .infinity)
        }
        guard !ds.isEmpty else { return .infinity }
        ds.sort()
        return ds[ds.count / 2]
    }

    /// How much lighter than its black route a dark blob has to be before
    /// it is shade rather than hold, and how much darker than the wall.
    /// On the third wall the black holds sat within a few points of the
    /// route's lightness, the shadow wedge under the beam fourteen above
    /// it, and the seam shadow ten; the grey wall sat thirty above those.
    static let shadeLift = 8.0
    /// And shade is never darker than this, whatever the route. A black
    /// route read as near black makes a chalk-dusted black hold at 13 to
    /// 18 look lifted; the dimmest shade on any wall sat at 27.
    static let shadeFloor = 27.0

    /// Whether a dark blob is wall in shadow rather than a black hold.
    ///
    /// Three things have to hold at once. The blob has no colour, so a
    /// dark purple hold in good light is not shade. It is clearly lighter
    /// than the route's own colour, so a black hold is not. And it is
    /// clearly darker than the wall round it, so a dark hold on a black
    /// panel, which is lighter than the panel, is not. The wall round it
    /// is whatever lies in a band just outside the blob, not the wall
    /// colour nearest the blob in Lab and not only the wall-coloured
    /// pixels in the band: the black overhang on the first wall is no
    /// wall colour at all, and judged against the chalk-dusted patches
    /// of it that pass for grey, every hold on it was called shade.
    private static func isShade(_ c: Component, in bmp: Bitmap, route: Lab, wall: [Lab]) -> Bool {
        guard !c.pixels.isEmpty, !wall.isEmpty else { return false }
        let step = max(1, c.pixels.count / 400)
        var ls: [Double] = [], chromas: [Double] = []
        var i = 0
        while i < c.pixels.count {
            let lab = bmp.lab(at: Int(c.pixels[i]))
            ls.append(lab.l); chromas.append((lab.a * lab.a + lab.b * lab.b).squareRoot())
            i += step
        }
        ls.sort(); chromas.sort()
        let l = ls[ls.count / 2], chroma = chromas[chromas.count / 2]
        guard chroma < groundChroma, l >= route.l + shadeLift, l >= shadeFloor else { return false }
        guard let around = surroundLightness(of: c, in: bmp) else { return false }
        return l <= around - shadeLift
    }

    /// How wide a band round a blob to read the wall from, in pixels.
    static let surroundBand = 4

    /// The median lightness of the pixels in a band just outside a blob,
    /// or nil when there are too few to read.
    private static func surroundLightness(of c: Component, in bmp: Bitmap) -> Double? {
        let (m, w, h) = c.local(width: bmp.width)
        var ls: [Double] = []
        let x0 = c.minX - 1 - surroundBand, y0 = c.minY - 1 - surroundBand
        for y in 0..<(h + 2 * surroundBand) {
            for x in 0..<(w + 2 * surroundBand) {
                let px = x0 + x, py = y0 + y
                guard px >= 0, py >= 0, px < bmp.width, py < bmp.height else { continue }
                // Inside the local box, and on the blob: skip.
                let lx = x - surroundBand, ly = y - surroundBand
                if lx >= 0, ly >= 0, lx < w, ly < h, m[ly * w + lx] { continue }
                ls.append(bmp.lab(at: py * bmp.width + px).l)
            }
        }
        guard ls.count >= 8 else { return nil }
        ls.sort()
        return ls[ls.count / 2]
    }

    /// The largest a black hold is, as a share of the picture. The black
    /// panel on the first wall came in pieces of several per cent each.
    static let darkSheet = 0.012
    /// A dark blob whose top edge is this much under a coloured route's
    /// pixels is a shadow the hold throws, not a hold.
    static let shadowShare = 0.4
    /// And it has to be the size of one: no bigger than this share of the
    /// picture. A black volume under a blue hold is a hold.
    static let shadowSize = 0.003

    /// Whether a dark blob is the shadow under a coloured hold: along its
    /// top edge, the pixels just above it are mostly another route's.
    private static func isShadow(_ c: Component, labels: [Int8], colored: [Bool], width: Int) -> Bool {
        var top: [Int: Int] = [:]
        for p in c.pixels {
            let i = Int(p), x = i % width, y = i / width
            if let t = top[x] { if y < t { top[x] = y } } else { top[x] = y }
        }
        var over = 0, n = 0
        for (x, y) in top where y >= 2 {
            n += 1
            for dy in 1...2 {
                let l = labels[(y - dy) * width + x]
                if l >= 0, Int(l) < colored.count, colored[Int(l)] { over += 1; break }
            }
        }
        return n > 0 && Double(over) / Double(n) >= shadowShare
    }

    /// Whether a blob sits on another route's hold rather than on the wall.
    private static func isPatch(_ c: Component, labels: [Int8], index: Int, colored: [Bool],
                                width: Int, height: Int, share: Double = patchShare) -> Bool {
        var other = 0, free = 0
        for p in c.pixels {
            let i = Int(p), x = i % width, y = i / width
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let l = labels[ny * width + nx]
                if l == Int8(index) { continue }
                if l < 0 { free += 1 }
                else if Int(l) < colored.count, colored[Int(l)] { other += 1 }
                // A neighbour on a grey or dark candidate is a shadow or the
                // wall under another name, and says nothing.
            }
        }
        return other + free > 0 && Double(other) / Double(other + free) > share
    }

    // MARK: Stickers

    /// The holds that are stickers, taken out.
    ///
    /// A start, a finish, a grade: the setters' tags are coloured, and every
    /// one came back as a hold of its colour, the yellow ones as a route of
    /// their own. Writing on a hold means it is not a hold. `text` is where
    /// the photograph had writing, normalised, from `readTags`.
    static func withoutStickers(_ swatches: [Swatch], text: [CGRect]) -> [Swatch] {
        guard !text.isEmpty else { return swatches }
        return swatches.compactMap { s in
            var copy = s
            copy.holds = s.holds.filter { h in
                !text.contains { t in
                    let overlap = h.rect.intersection(t)
                    return !overlap.isNull && overlap.width * overlap.height >= 0.3 * h.rect.width * h.rect.height
                }
            }
            return copy.holds.count >= minimumHolds ? copy : nil
        }
    }

    /// The holds that are on the wall, between the mat and the top.
    static func onTheWall(_ swatches: [Swatch], reading: FaceEngine.Reading, width: Int, height: Int) -> [Swatch] {
        guard reading.floor != nil || reading.top != nil else { return swatches }
        return swatches.compactMap { s in
            var copy = s
            copy.holds = s.holds.filter {
                reading.onTheWall(CGPoint(x: $0.rect.midX, y: $0.rect.midY), width: width, height: height)
            }
            return copy.holds.count >= minimumHolds ? copy : nil
        }
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
    /// The share of a colour's pixels that have to sit in hold-sized blobs,
    /// neither speckle nor sheet, for the colour to be a route. On the two
    /// real walls every route is at 0.73 or above and every shade of wall and
    /// shadow at 0.47 or below.
    static let routePurity = 0.6

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
    /// - Parameter excluding: pixels at `paletteWidth` to read nothing
    ///   from, the people in the shot. See `PeopleEngine`.
    static func palette(in image: CGImage, tolerance: Double = 30,
                        limit: Int = 10, excluding: [Bool]? = nil) -> [Swatch] {
        guard var bmp = Bitmap(image, targetWidth: paletteWidth) else { return [] }
        if let excluding, excluding.count == bmp.width * bmp.height { bmp.excluded = excluding }

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
                // A grey, and a muted colour too, has to stand clear of the
                // wall. Glare on a grey-blue panel comes back faintly pink
                // and a lit slab faintly cream, each a shade of the wall
                // with a little colour in it, and each was offered as a
                // route of forty holds.
                guard chroma < mutedChroma else { return true }
                let nearest = ground.map { $0.distance(to: c.lab) }.min() ?? .infinity
                if nearest >= neutralClearance { return true }
                // A muted colour that is clearly its own hue and clearly
                // lighter or darker than the wall is a route: the blue on
                // the second wall is both. Glare is the wall's own
                // lightness with a little colour in it, and is neither.
                guard chroma >= groundChroma else { return false }
                return ground.allSatisfy { g in
                    let hueDistance = ((g.a - c.lab.a) * (g.a - c.lab.a) + (g.b - c.lab.b) * (g.b - c.lab.b)).squareRoot()
                    return hueDistance >= mutedHueClearance && abs(g.l - c.lab.l) >= mutedLightnessClearance
                }
            }
        // One hue, one route. A yellow hold in the light, the same hold in
        // shadow and the same hold under chalk sit far apart in Lab, and the
        // histogram keeps them as three colours; each then got a third of the
        // route and the rest of its boxes went to its neighbours. Shades of
        // one hue are joined here and their holds pooled.
        let families = hueFamilies(candidates)
        var labels = segment(bmp, colors: candidates.map(\.lab), tolerance: tolerance,
                             ground: ground)
        var family = [Int8](repeating: -1, count: candidates.count)
        for (f, members) in families.enumerated() { for m in members { family[m] = Int8(f) } }
        for i in labels.indices where labels[i] >= 0 { labels[i] = family[Int(labels[i])] }
        let joined = families.map { members in
            members.map { candidates[$0] }.max { $0.count < $1.count }!
        }
        var swatches: [Swatch] = []
        let total = Double(bmp.width * bmp.height)
        for (i, candidate) in joined.enumerated() {
            // A route is made of holds. A shade of the wall that happens to
            // leave a few hold-shaped scraps behind has most of its pixels in
            // speckle too small to be anything and in panels too big to be a
            // hold. On a wall of grey-blue panels in uneven light two such
            // shades led the list, boxed the wall, and were called routes.
            // Judged on size alone, not shape: the orange route on the first
            // wall is long curvy holds that fail the shape test and are holds.
            var mask = [Bool](repeating: false, count: labels.count)
            var labelled = 0
            for j in labels.indices where labels[j] == Int8(i) { mask[j] = true; labelled += 1 }
            let sized = blobs(in: bmp, mask: &mask)
                .filter { $0.area <= maxAreaFraction }
                .reduce(0.0) { $0 + $1.area } * total
            guard labelled > 0, sized / Double(labelled) >= routePurity else { continue }
            let found = holds(in: bmp, labels: &labels, index: i, colors: joined.map(\.lab), ground: ground)
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
        let ground = groundColors(in: bmp)
        var labels = segment(bmp, colors: colors, tolerance: tolerance, ground: ground)
        return holds(in: bmp, labels: &labels, index: index, colors: colors, ground: ground)
    }

    // MARK: Shades of one hue

    /// How far apart in hue two colours can be and still be one route, in
    /// radians. About twenty degrees: orange and pink on the third wall are
    /// twenty-six apart, the two pinks ten.
    static let familyHue = 0.35
    /// And how much more saturated one can be than the other. A yellow hold
    /// in shadow keeps about three quarters of its chroma; a cream hold has
    /// under half of a yellow one's, and is a different route.
    static let familyChroma = 1.6
    /// Below this chroma a colour has no hue worth grouping on.
    static let familyMinChroma = 20.0

    /// Candidates grouped by hue, each group led by its most common member.
    /// Membership is judged against the leader, not the last member joined,
    /// so a chain cannot walk from orange through yellow into green.
    static func hueFamilies(_ candidates: [Candidate]) -> [[Int]] {
        func chroma(_ l: Lab) -> Double { (l.a * l.a + l.b * l.b).squareRoot() }
        func hue(_ l: Lab) -> Double { atan2(l.b, l.a) }
        var families: [[Int]] = []
        for i in candidates.indices.sorted(by: { candidates[$0].count > candidates[$1].count }) {
            let c = candidates[i].lab
            var joined = false
            if chroma(c) >= familyMinChroma {
                for f in families.indices {
                    let lead = candidates[families[f][0]].lab
                    guard chroma(lead) >= familyMinChroma else { continue }
                    var dh = abs(hue(c) - hue(lead))
                    if dh > .pi { dh = 2 * .pi - dh }
                    let ratio = max(chroma(c), chroma(lead)) / min(chroma(c), chroma(lead))
                    if dh < familyHue, ratio <= familyChroma { families[f].append(i); joined = true; break }
                }
            }
            if !joined { families.append([i]) }
        }
        return families
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
    /// Below this chroma a candidate is muted enough to be a shade of the
    /// wall, and is held to the same clearance as a grey. A real muted
    /// route, the blue on the second wall at 21, stands thirty from its
    /// wall; glare stands under twenty.
    static let mutedChroma = 28.0
    static let mutedHueClearance = 18.0
    static let mutedLightnessClearance = 8.0
    /// A pixel this faintly coloured, and darker than a route, can still be
    /// that route's hold in deep shadow. Below it there is no hue to read.
    static let shadowChroma = 7.0
    /// Only a clearly coloured route claims shadow pixels by hue alone; a
    /// muted one would claim the wall.
    static let shadowCandidateChroma = 24.0
    /// Hue agreement for a shadow pixel, in radians. About thirty degrees.
    static let shadowHue = 0.5
    /// How far, in pixels at working width, a route may grow into its shadow.
    static let shadowGrow = 10

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

    /// A neutral this dark is not a wall: walls are mid grey, and what is near
    /// black on one is a black route, a shadow under a volume, or a bolt
    /// hole. Those are told apart by shape below, not written off here. On
    /// the fourth wall the black route and its shadows together covered five
    /// per cent of the picture and the route was never offered.
    static let darkHold = 35.0

    static func isScenery(_ lab: Lab, in bmp: Bitmap) -> Bool {
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        if chroma < groundChroma, lab.l >= darkHold { return true }
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
        var shadow = [Int8](repeating: -1, count: bmp.width * bmp.height)
        guard !colors.isEmpty, colors.count < 127 else { return labels }
        for i in 0..<(bmp.width * bmp.height) {
            if bmp.isExcluded(i) { continue }
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

            // Deep shadow. A small hold under a volume keeps its hue and loses
            // nearly everything else: chroma falls under the grey line and
            // every distance above fails. What survives is the direction of
            // the colour. A dim pixel still faintly the route's hue, and darker
            // than the route, is noted here and adopted below, but only next to
            // a pixel already the route's: a shaded face touches a lit one. By
            // hue alone, without that, the dark panel on the first wall came
            // back as thirty boxes of yellow.
            if nearest < 0, chroma >= shadowChroma, chroma < groundChroma {
                let hue = atan2(lab.b, lab.a)
                for (j, color) in colors.enumerated() {
                    let cChroma = (color.a * color.a + color.b * color.b).squareRoot()
                    guard cChroma >= shadowCandidateChroma, lab.l < color.l else { continue }
                    var dh = abs(hue - atan2(color.b, color.a))
                    if dh > .pi { dh = 2 * .pi - dh }
                    if dh < shadowHue { shadow[i] = Int8(j); break }
                }
            }
        }

        // Grow the routes into their own shadows, a ring at a time.
        let w = bmp.width, h = bmp.height
        for _ in 0..<shadowGrow {
            var adopted: [(Int, Int8)] = []
            for i in 0..<(w * h) where labels[i] < 0 && shadow[i] >= 0 {
                let x = i % w, y = i / w, want = shadow[i]
                if (x > 0 && labels[i - 1] == want) || (x < w - 1 && labels[i + 1] == want)
                    || (y > 0 && labels[i - w] == want) || (y < h - 1 && labels[i + w] == want) {
                    adopted.append((i, want))
                }
            }
            if adopted.isEmpty { break }
            for (i, j) in adopted { labels[i] = j }
        }
        return labels
    }

    static func holds(in bmp: Bitmap, labels: inout [Int8], index: Int, colors: [Lab] = [],
                      ground: [Lab] = []) -> [Hold] {
        var mask = [Bool](repeating: false, count: labels.count)
        for i in labels.indices { mask[i] = labels[i] == Int8(index) }
        return holds(in: bmp, mask: &mask, labels: labels, index: index, colors: colors, ground: ground)
    }

    /// A lump fills this much of its own convex hull. A crescent fills about
    /// half, a chalked black hold with the chalk read as cream about a third;
    /// a ring of glare round a panel, under a quarter.
    static let lumpFill = 0.1
    /// A blob enclosing this much background, against its own pixels, is a
    /// ring: the ring on the fourth wall enclosed several times its own
    /// area.
    static let hollow = 0.5
    /// A blob whose edge touches another route's pixels more than it touches
    /// wall is a patch on that route's hold: chalk on a green sloper read as
    /// a white hold, the lit face of a red hold read as orange.
    static let patchShare = 0.5
    /// Below this chroma a candidate is white, cream, grey or black: the
    /// colours chalk and shadow come in, and the only ones the patch rule
    /// is applied to.
    static let paleChroma = 40.0
    static let paleLightness = 70.0
    /// And a white blob is a patch when this much of its edge is on a
    /// coloured route: chalk on a lip hangs over the edge of the hold.
    static let chalkPatchShare = 0.25

    /// White, cream, grey or black: chalk and shadow come in these, and a
    /// muted blue does not.
    static func isPale(_ c: Lab) -> Bool {
        let chroma = (c.a * c.a + c.b * c.b).squareRoot()
        return chroma < groundChroma || (c.l >= paleLightness && chroma < paleChroma)
    }

    /// Chalk is bright and has little hue: lighter than this and under the
    /// pale line in chroma. Not the grey line: where chalk meets the hold's
    /// colour the pixels blend, and judged by the grey line that blended
    /// rim walled the chalk off from the hold it sits on.
    static let chalkLightness = 62.0
    /// How much of a chalk patch's edge has to lie against the hold for
    /// the patch to be the hold's. Chalk on a hold borders the hold along
    /// most of its edge, and chalk in a bay or a hole along all of it; a
    /// white hold leaning on a green one touches it along a sliver.
    static let chalkTouch = 0.35
    /// And a runaway: a patch past this many times the hold's own size
    /// is a white panel, whatever it touches.
    static let chalkRunaway = 4.0

    /// White pixels, the colour chalk comes in.
    static func isChalk(_ c: Lab) -> Bool {
        c.l >= chalkLightness && (c.a * c.a + c.b * c.b).squareRoot() < paleChroma
    }

    /// Give a coloured blob the chalk sitting on it: every chalk pixel
    /// reached from its edge, so long as the patch lies against the blob
    /// along enough of the patch's own edge. Judged by size instead, a
    /// sloper that is mostly chalk lost its top half, and a chalk bay
    /// left a crescent.
    private static func adoptChalk(into component: inout Component, chalk: inout [Bool],
                                   width: Int, height: Int) {
        let cap = Int(Double(component.count) * chalkRunaway)
        guard cap > 0 else { return }
        var mine = Set<Int32>(component.pixels)
        var taken: [Int] = []
        var stack: [Int] = []
        for p in component.pixels {
            let i = Int(p), x = i % width, y = i / width
            if x > 0, chalk[i - 1] { stack.append(i - 1) }
            if x < width - 1, chalk[i + 1] { stack.append(i + 1) }
            if y > 0, chalk[i - width] { stack.append(i - width) }
            if y < height - 1, chalk[i + width] { stack.append(i + width) }
        }
        while let i = stack.popLast() {
            guard chalk[i] else { continue }
            chalk[i] = false
            taken.append(i)
            if taken.count > cap { break }
            let x = i % width, y = i / width
            if x > 0, chalk[i - 1] { stack.append(i - 1) }
            if x < width - 1, chalk[i + 1] { stack.append(i + 1) }
            if y > 0, chalk[i - width] { stack.append(i - width) }
            if y < height - 1, chalk[i + width] { stack.append(i + width) }
        }
        var keep = taken.count <= cap
        if keep {
            // The patch's edge: every non-patch neighbour of a patch
            // pixel, counted as hold or as something else.
            let patch = Set<Int32>(taken.map { Int32($0) })
            var hold = 0, other = 0
            for i in taken {
                let x = i % width, y = i / width
                for j in [x > 0 ? i - 1 : -1, x < width - 1 ? i + 1 : -1, y > 0 ? i - width : -1, y < height - 1 ? i + width : -1] where j >= 0 {
                    if patch.contains(Int32(j)) { continue }
                    if mine.contains(Int32(j)) { hold += 1 } else { other += 1 }
                }
            }
            keep = hold + other > 0 && Double(hold) / Double(hold + other) >= chalkTouch
        }
        if !keep {
            for i in taken { chalk[i] = true }
            return
        }
        for i in taken { component.add(i % width, i / width, index: i); mine.insert(Int32(i)) }
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
            if bmp.isExcluded(i) { continue }
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
        comp.keepsPixels = true
        var stack = [start]
        mask[start] = false
        while let i = stack.popLast() {
            let px = i % bmp.width, py = i / bmp.width
            comp.add(px, py, index: i)
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
                    area: Double(comp.count) / total,
                    outline: comp.outline(width: bmp.width, height: bmp.height))
    }

    // MARK: Connected components

    private struct Component {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var count = 0
        /// Every pixel, kept only when an outline or a neighbourhood is wanted.
        var pixels: [Int32] = []
        var keepsPixels = false
        mutating func add(_ x: Int, _ y: Int, index: Int) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            count += 1
            if keepsPixels { pixels.append(Int32(index)) }
        }

        var boxWidth: Int { maxX - minX + 1 }
        var boxHeight: Int { maxY - minY + 1 }

        /// The blob as a small mask of its own box, with a one pixel margin.
        func local(width: Int) -> (mask: [Bool], w: Int, h: Int) {
            let w = boxWidth + 2, h = boxHeight + 2
            var m = [Bool](repeating: false, count: w * h)
            for p in pixels {
                let x = Int(p) % width - minX + 1, y = Int(p) / width - minY + 1
                m[y * w + x] = true
            }
            return (m, w, h)
        }

        /// How many pixels the traced boundary ran, set by `boundary`.
        var perimeterCache = 0

        /// How many times the blob can be eroded by a pixel before nothing
        /// is left: its largest inscribed half-width. A pen stroke round a
        /// hold is a closed loop, and judged by area over perimeter a
        /// loop looks as thick as a snake, because the trace runs round
        /// its outside only. Eroded, a stroke is gone in two; a hold is
        /// not.
        func depth(width: Int) -> Int {
            var (m, w, h) = local(width: width)
            var steps = 0
            while m.contains(true) {
                var next = m
                for y in 0..<h { for x in 0..<w where m[y * w + x] {
                    let i = y * w + x
                    if x == 0 || y == 0 || x == w - 1 || y == h - 1
                        || !m[i - 1] || !m[i + 1] || !m[i - w] || !m[i + w] { next[i] = false }
                } }
                m = next
                steps += 1
                if steps > 64 { break }
            }
            return steps
        }

        /// How thick the blob is, in pixels: twice its area over its
        /// perimeter, which for a ribbon is the ribbon's width. A shadow
        /// line down an arete is a pixel or two; a snake of a hold is many.
        mutating func thickness(width: Int) -> Double {
            if perimeterCache == 0 { _ = boundary(width: width) }
            return perimeterCache > 0 ? 2 * Double(count) / Double(perimeterCache) : 0
        }

        /// The boundary, traced round the blob, as points in the bitmap.
        ///
        /// Square tracing on the blob's own mask: walk the edge keeping the
        /// blob on the right, which follows a U into its bend where a hull
        /// bridges it. Thinned to a few dozen points for drawing.
        mutating func boundary(width: Int) -> [(Int, Int)] {
            let out = fullBoundary(width: width)
            let step = max(1, out.count / 48)
            var thinned: [(Int, Int)] = []
            for (i, p) in out.enumerated() where i % step == 0 { thinned.append(p) }
            return thinned
        }

        /// The boundary with the pixel staircase averaged out: each point is
        /// the mean of a window of its neighbours round the loop. Still
        /// thinned to a few dozen points, which the drawing then runs a
        /// curve through.
        mutating func smoothBoundary(width: Int) -> [(Double, Double)] {
            let trace = fullBoundary(width: width)
            guard trace.count >= 3 else { return trace.map { (Double($0.0), Double($0.1)) } }
            let n = trace.count
            let half = max(1, min(6, n / 12))
            var smooth: [(Double, Double)] = []
            smooth.reserveCapacity(n)
            for i in 0..<n {
                var sx = 0.0, sy = 0.0
                for k in -half...half {
                    let p = trace[((i + k) % n + n) % n]
                    sx += Double(p.0); sy += Double(p.1)
                }
                let c = Double(2 * half + 1)
                smooth.append((sx / c, sy / c))
            }
            let step = max(1, n / 40)
            var thinned: [(Double, Double)] = []
            for (i, p) in smooth.enumerated() where i % step == 0 { thinned.append(p) }
            return thinned
        }

        /// The whole traced loop in bitmap coordinates, unthinned.
        private mutating func fullBoundary(width: Int) -> [(Int, Int)] {
            let (m, w, _) = local(width: width)
            func on(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y * w + x < m.count && m[y * w + x] }
            guard let startIndex = m.firstIndex(of: true) else { return [] }
            let sx = startIndex % w, sy = startIndex / w
            let dirs = [(-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1)]
            var out: [(Int, Int)] = [(sx, sy)]
            var cx = sx, cy = sy
            var back = 0
            let limit = 4 * (w + m.count / w) + 8
            repeat {
                var found = false
                for k in 0..<8 {
                    let d = (back + k) % 8
                    let nx = cx + dirs[d].0, ny = cy + dirs[d].1
                    if on(nx, ny) {
                        cx = nx; cy = ny
                        back = (d + 5) % 8
                        out.append((cx, cy))
                        found = true
                        break
                    }
                }
                if !found { break }
            } while !(cx == sx && cy == sy) && out.count < limit
            if out.count > 1, out.last! == (sx, sy) { out.removeLast() }
            perimeterCache = out.count
            return out.map { ($0.0 + minX - 1, $0.1 + minY - 1) }
        }

        /// The outline, normalised to the bitmap.
        mutating func outline(width: Int, height: Int) -> [CGPoint] {
            smoothBoundary(width: width).map {
                CGPoint(x: ($0.0 + 0.5) / Double(width), y: ($0.1 + 0.5) / Double(height))
            }
        }

        /// The share of the blob's own box that is background enclosed by
        /// the blob: a hole. A ring of glare round a panel has one; a snake
        /// of a hold has bays that open to the outside, and none. Found by
        /// flooding the background in from the box's margin and seeing what
        /// background is left.
        func holeShare(width: Int, isWall: (Int) -> Bool) -> Double {
            let (m, w, h) = local(width: width)
            var seen = [Bool](repeating: false, count: w * h)
            var stack: [Int] = []
            for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
            for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
            while let i = stack.popLast() {
                guard i >= 0, i < w * h, !seen[i], !m[i] else { continue }
                seen[i] = true
                let x = i % w, y = i / w
                if x > 0 { stack.append(i - 1) }
                if x < w - 1 { stack.append(i + 1) }
                if y > 0 { stack.append(i - w) }
                if y < h - 1 { stack.append(i + w) }
            }
            // Only wall counts as hole. Chalk inside a black hold is not
            // wall, whether or not any route claimed it.
            var holes = 0
            for i in 0..<(w * h) where !m[i] && !seen[i] {
                let x = i % w - 1 + minX, y = i / w - 1 + minY
                guard x >= 0, y >= 0, x < width else { continue }
                if isWall(y * width + x) { holes += 1 }
            }
            return Double(holes) / Double(max(count, 1))
        }

        /// How much of its own convex hull the blob fills. A lump fills
        /// nearly all of it; a ring of glare round a panel, a shadow along two
        /// sides of a volume, fills a fraction and used to be drawn as a large
        /// empty polygon.
        mutating func hullFill(width: Int) -> Double {
            let hull = RouteScanner.hull(boundary(width: width))
            guard hull.count >= 3 else { return 1 }
            var a = 0.0
            for i in hull.indices {
                let p = hull[i], q = hull[(i + 1) % hull.count]
                a += Double(p.0 * q.1 - q.0 * p.1)
            }
            let area = abs(a) / 2
            return area < 1 ? 1 : min(1, Double(count) / area)
        }
    }

    /// Convex hull by monotone chain. Integer points, so there is no rounding
    /// to argue with; counter-clockwise in image coordinates.
    static func hull(_ input: [(Int, Int)]) -> [(Int, Int)] {
        struct P: Hashable { let x: Int; let y: Int }
        var seen = Set<P>()
        for q in input { seen.insert(P(x: q.0, y: q.1)) }
        var pts: [(Int, Int)] = seen.map { ($0.x, $0.y) }
        pts.sort { a, b in a.0 != b.0 ? a.0 < b.0 : a.1 < b.1 }
        guard pts.count >= 3 else { return pts }
        func cross(_ o: (Int, Int), _ a: (Int, Int), _ b: (Int, Int)) -> Int {
            (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
        }
        var lower: [(Int, Int)] = []
        for p in pts {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [(Int, Int)] = []
        for p in pts.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    /// Flood fill with an explicit stack. Recursion would blow the stack on a
    /// large blob, and a wall photo has plenty of those.
    private static func components(mask: inout [Bool], width: Int, height: Int,
                                   minPixels: Int, maxPixels: Int,
                                   outlines: Bool = false) -> [Component] {
        var out: [Component] = []
        var stack: [Int] = []

        for start in 0..<(width * height) where mask[start] {
            var comp = Component()
            comp.keepsPixels = outlines
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            mask[start] = false

            while let i = stack.popLast() {
                let x = i % width, y = i / width
                comp.add(x, y, index: i)
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

    /// A start or finish sticker, and where it is.
    struct Tag: Equatable {
        enum Kind { case start, finish }
        let kind: Kind
        /// Normalised, origin top left.
        let point: CGPoint
    }

    /// Everything written on the wall, read off the photograph: the start
    /// and finish stickers with their kind, and where every piece of writing
    /// is, so no sticker is taken for a hold. Empty where nothing can be read.
    static func readTags(in image: CGImage) async -> (tags: [Tag], text: [CGRect]) {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var tags: [Tag] = []
                var boxes: [CGRect] = []
                for o in observations {
                    guard let text = o.topCandidates(1).first?.string.lowercased() else { continue }
                    let b = o.boundingBox
                    boxes.append(CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
                    let point = CGPoint(x: b.midX, y: 1 - b.midY)
                    if text.contains("start") { tags.append(Tag(kind: .start, point: point)) }
                    else if text.contains("finish") || text.contains("top") { tags.append(Tag(kind: .finish, point: point)) }
                }
                continuation.resume(returning: (tags, boxes))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: ([], [])) }
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
    /// Pixels that are not the wall and not a route: the people standing
    /// in the shot. No colour is read from them.
    var excluded: [Bool]? = nil

    /// Whether a pixel is one nothing should be read from.
    func isExcluded(_ index: Int) -> Bool {
        guard let excluded, index < excluded.count else { return false }
        return excluded[index]
    }

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

    init(hexString: String) {
        let cleaned = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        let v = UInt32(cleaned, radix: 16) ?? 0x888888
        self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

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
