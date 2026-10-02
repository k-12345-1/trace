import Foundation
import CoreGraphics

/// The faces of a wall, read from the seams between them.
///
/// A bouldering wall is panels at angles, and the seams where they meet are
/// the long straight lines in a photograph of one: a shadow down an arete,
/// a step in lightness where a slab turns into an overhang. A route is set
/// on a face. Holds of its colour on the far side of a seam are usually a
/// different route, and on the fifth wall the white and orange routes each
/// picked up holds from the panel next door.
///
/// The lines are found with a Hough transform over the dark and the sharply
/// lit-to-shaded pixels, then each candidate is walked to make sure it is a
/// line and not a row of bolt holes: a seam is continuous, a row of holes
/// is five per cent of one. Each line splits the picture in two, and a
/// hold's face is which side of every line it falls.
enum FaceEngine {

    struct Line: Equatable {
        /// Normal form: x cos θ + y sin θ = ρ, in bitmap pixels.
        let theta: Double
        let rho: Double
        /// Share of the line's run across the picture that is seam.
        let support: Double
        /// Where along x, in bitmap pixels, the seam was actually found.
        /// A line runs across the whole picture; the edge it was read
        /// from may not. The top of the first wall is a straight edge
        /// across the grey panels, and past them a black overhang runs
        /// on up to the ceiling with holds the whole way.
        var run: ClosedRange<Double>? = nil

        /// Which side of the line a point is on, in bitmap pixels.
        func side(_ p: CGPoint) -> Bool {
            p.x * cos(theta) + p.y * sin(theta) - rho >= 0
        }

        /// The line's y at a given x, in bitmap pixels. Nil for a vertical.
        func y(atX x: Double) -> Double? {
            let s = sin(theta)
            guard abs(s) > 1e-6 else { return nil }
            return (rho - x * cos(theta)) / s
        }

        /// Whether the edge was seen at this x, with slack of a few per
        /// cent of the picture. True when no run was recorded.
        func covers(x: Double, width: Int) -> Bool {
            guard let run else { return true }
            let slack = Double(width) * FaceEngine.runSlack
            return x >= run.lowerBound - slack && x <= run.upperBound + slack
        }

        /// Where it crosses the picture, normalised, for drawing and tests.
        func endpoints(width: Int, height: Int) -> (CGPoint, CGPoint)? {
            let w = Double(width), h = Double(height)
            var pts: [CGPoint] = []
            let c = cos(theta), s = sin(theta)
            if abs(s) > 1e-6 {
                for x in [0.0, w] { let y = (rho - x * c) / s; if y >= 0, y <= h { pts.append(CGPoint(x: x / w, y: y / h)) } }
            }
            if abs(c) > 1e-6 {
                for y in [0.0, h] { let x = (rho - y * s) / c; if x >= 0, x <= w { pts.append(CGPoint(x: x / w, y: y / h)) } }
            }
            guard pts.count >= 2 else { return nil }
            return (pts[0], pts[pts.count - 1])
        }
    }

    /// A seam pixel is darker than the wall by this much in L, or sits on a
    /// step in L this big between its neighbours.
    static let darker = 14.0
    static let step = 10.0
    /// Within the longest run, this share of the samples has to be seam. A
    /// seam behind a few holds is most of its length; a row of bolt holes is
    /// a twentieth of one.
    static let minimumSupport = 0.5
    /// And the run has to be at least this share of the picture's diagonal.
    static let minimumRun = 0.35
    /// How far a run may go without seam before it ends: the width of a hold
    /// sitting on the seam, at working width.
    static let maximumGap = 24
    /// Pixels in from the picture's edge that are ignored, so the frame of
    /// the photograph is not read as a seam.
    static let border = 3
    static let angleStep = 2.0
    /// Lines closer than this in angle (degrees) and offset (pixels) are one.
    static let mergeAngle = 14.0
    static let mergeRho = 30.0
    /// A seam is thin. Within a window this wide, seam pixels have to be a
    /// minority, or the pixel is in a shadowed panel, not on a line.
    static let thinWindow = 4
    static let thinShare = 0.45
    /// The most seams a wall is given. A photograph has a handful of panels.
    static let mostLines = 5
    /// The floor and the top. A line this close to horizontal, in degrees,
    /// low in the picture is the mat meeting the wall; high in the picture
    /// it is the wall meeting the ceiling. Neither is a seam between panels:
    /// the ground is a horizontal plane and no route is on it, and nothing
    /// is climbed above the wall. In between, a near-horizontal line is a
    /// roof's lip and counts.
    /// The mat sits low and nearly level, with the lean perspective gives
    /// it. On the fourth wall a volume's edge at seventeen degrees, seventy
    /// per cent of the way down, passed for the floor and took twenty holds.
    static let floorTilt = 20.0
    static let floorFrom = 0.8
    /// The ceiling sits high and level. On the first wall the lip of the
    /// overhang, a quarter of the way down, passed for the top.
    static let topTilt = 12.0
    /// How far down the picture the top of the wall may sit. A fifth was
    /// not enough: on the sixth wall the edge sat at a fifth and a
    /// hair, and the light rail above it passed for the top instead.
    static let topTo = 0.35
    /// A top has wall under it and something else over it: at least this
    /// share of samples just below the edge are wall-coloured, and at most
    /// `notWallAbove` of those just above. The lip of an overhang has wall
    /// above it; a light rail has ceiling below it; neither is the top.
    static let wallBelow = 0.5
    static let notWallAbove = 0.35
    /// How far from the edge the bands are read, in pixels at working width.
    static let bandNear = 6, bandFar = 16

    static func isFloor(_ line: Line, width: Int, height: Int) -> Bool {
        let tilt = abs(line.theta * 180 / .pi - 90)
        guard let (a, b) = line.endpoints(width: width, height: height) else { return false }
        let y = (a.y + b.y) / 2
        return (tilt <= floorTilt && y >= floorFrom) || (tilt <= topTilt && y <= topTo)
    }

    /// Seam pixels: dark lines and lightness steps, among low chroma pixels.
    static func seamMask(_ bmp: Bitmap, wallL: Double) -> [Bool] {
        let w = bmp.width, h = bmp.height
        var dark = [Bool](repeating: false, count: w * h)
        var edge = [Bool](repeating: false, count: w * h)
        for y in border..<(h - border) {
            for x in border..<(w - border) {
                let i = y * w + x
                let lab = bmp.lab(at: i)
                guard (lab.a * lab.a + lab.b * lab.b).squareRoot() < RouteScanner.groundChroma else { continue }
                if lab.l <= wallL - darker { dark[i] = true; continue }
                let dx = abs(bmp.lab(at: i + 1).l - bmp.lab(at: i - 1).l)
                let dy = abs(bmp.lab(at: i + w).l - bmp.lab(at: i - w).l)
                if max(dx, dy) >= step { edge[i] = true }
            }
        }
        // Thin: a sheet of dark is not a line. Judged on the dark pixels
        // alone; the step pixels either side of a dark line are thin by
        // nature, and counted they fattened every line into a sheet.
        var mask = edge
        for y in border..<(h - border) {
            for x in border..<(w - border) where dark[y * w + x] {
                var on = 0, n = 0
                for oy in -thinWindow...thinWindow { for ox in -thinWindow...thinWindow {
                    let nx = x + ox, ny = y + oy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    n += 1; if dark[ny * w + nx] { on += 1 }
                } }
                if Double(on) / Double(n) <= thinShare { mask[y * w + x] = true }
            }
        }
        return mask
    }

    /// What the lines say about the wall: the seams between its panels,
    /// and where the wall ends. The floor line is the highest near-horizontal
    /// line low in the picture, the top line the lowest one high in it, so
    /// that between them lies the wall and nothing else.
    struct Reading {
        var seams: [Line]
        var floor: Line?
        var top: Line?

        /// Whether a point, normalised, is on the wall: not below the mat
        /// and not above the top. Glare on the ceiling and a stripe on the
        /// padding are not holds, however hold shaped they are.
        func onTheWall(_ p: CGPoint, width: Int, height: Int) -> Bool {
            let q = CGPoint(x: p.x * Double(width), y: p.y * Double(height))
            if let floor, let y = floor.y(atX: q.x), q.y > y { return false }
            // The top counts only where it was seen, with a little slack:
            // past the end of the edge the wall may well carry on up.
            if let top, let y = top.y(atX: q.x), q.y < y, top.covers(x: q.x, width: width) { return false }
            return true
        }
    }

    static func lines(in bmp: Bitmap) -> [Line] { read(in: bmp).seams }

    static func read(in bmp: Bitmap) -> Reading {
        // The wall's lightness is the most common colour's. Cheaper than the
        // full ground read, which walks every blob of every colour and took
        // three seconds on the second wall for a number this needs roughly.
        let wallL = RouteScanner.commonColors(in: bmp, step: 12, keep: 1, apart: 1).first?.lab.l ?? 60
        return read(in: bmp, wallL: wallL)
    }

    static func lines(in bmp: Bitmap, wallL: Double) -> [Line] { read(in: bmp, wallL: wallL).seams }

    static func read(in bmp: Bitmap, wallL: Double) -> Reading {
        let w = bmp.width, h = bmp.height
        let mask = seamMask(bmp, wallL: wallL)
        let diag = (Double(w * w + h * h)).squareRoot()
        let angles = Int(180 / angleStep)
        let rhoBins = Int(2 * diag) + 1
        var acc = [Int](repeating: 0, count: angles * rhoBins)
        var cosT = [Double](), sinT = [Double]()
        for a in 0..<angles { let t = Double(a) * angleStep * .pi / 180; cosT.append(cos(t)); sinT.append(sin(t)) }
        for y in 0..<h { for x in 0..<w where mask[y * w + x] {
            for a in 0..<angles {
                let rho = Double(x) * cosT[a] + Double(y) * sinT[a]
                let r = Int(rho + diag)
                if r >= 0, r < rhoBins { acc[a * rhoBins + r] += 1 }
            }
        } }

        // Candidates: bins with enough votes, strongest first, verified by
        // walking the line and merged with anything already taken.
        let needed = Int(diag * minimumRun * minimumSupport)
        var candidates: [(Int, Int, Int)] = []
        for a in 0..<angles { for r in 0..<rhoBins where acc[a * rhoBins + r] >= needed { candidates.append((acc[a * rhoBins + r], a, r)) } }
        candidates.sort { $0.0 > $1.0 }
        var out = Reading(seams: [], floor: nil, top: nil)
        var taken: [Line] = []
        for (_, a, r) in candidates.prefix(160) {
            let theta = Double(a) * angleStep * .pi / 180
            let rho = Double(r) - diag
            if taken.contains(where: { near($0, theta: theta, rho: rho) }) { continue }
            if let (support, run) = walk(theta: theta, rho: rho, mask: mask, width: w, height: h, diag: diag) {
                let line = Line(theta: theta, rho: rho, support: support, run: run)
                taken.append(line)
                if isFloor(line, width: w, height: h) {
                    // The floor is the highest such line, the top the lowest:
                    // the wall is what lies between them.
                    let y = line.y(atX: Double(w) / 2) ?? 0
                    if y >= Double(h) * floorFrom * 0.98 {
                        if let f = out.floor, let fy = f.y(atX: Double(w) / 2), fy <= y { } else { out.floor = line }
                        continue
                    }
                    // A top only where the wall stops: wall under the edge
                    // and not over it. Otherwise it is a seam like any other.
                    if hasWallBelow(line, bmp: bmp, wallL: wallL) {
                        if let t = out.top, let ty = t.y(atX: Double(w) / 2), ty >= y { } else { out.top = line }
                        continue
                    }
                }
                out.seams.append(line)
                if out.seams.count >= mostLines { break }
            }
        }
        if out.top == nil { out.top = topByProfile(bmp, wallL: wallL) }
        return out
    }

    /// The top of the wall read as a change of colour rather than as a
    /// line. On the sixth wall the ceiling shades into the wall over a
    /// tenth of the picture, with no edge for a seam to be found on, and
    /// the fittings on the ceiling were holds. Row by row from the top:
    /// the row where wall-coloured pixels take over below and are rare
    /// above, the best such row within the top third, is the top.
    static func topByProfile(_ bmp: Bitmap, wallL: Double) -> Line? {
        let w = bmp.width, h = bmp.height
        var share = [Double](repeating: 0, count: h)
        for y in 0..<h {
            var wall = 0, n = 0
            for x in stride(from: 0, to: w, by: 3) {
                n += 1
                let lab = bmp.lab(at: y * w + x)
                if abs(lab.l - wallL) < profileReach && (lab.a * lab.a + lab.b * lab.b).squareRoot() < RouteScanner.groundChroma { wall += 1 }
            }
            share[y] = Double(wall) / Double(max(n, 1))
        }
        func mean(_ a: Int, _ b: Int) -> Double {
            let lo = max(0, a), hi = min(h - 1, b)
            guard hi >= lo else { return 0 }
            return share[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
        var best: (y: Int, gap: Double)?
        for y in bandFar..<Int(Double(h) * topTo) {
            // Above the top it is ceiling all the way up: the whole strip,
            // not a band. A band just over a row of big holds has little
            // wall in it, and the second wall got a top under its finish
            // holds.
            let below = mean(y + bandNear, y + bandFar), above = mean(0, y - bandNear)
            guard below >= wallBelow, above <= notWallAbove else { continue }
            if best == nil || below - above > best!.gap { best = (y, below - above) }
        }
        guard let best else { return nil }
        return Line(theta: .pi / 2, rho: Double(best.y), support: best.gap, run: 0...Double(w - 1))
    }

    /// How far from the wall's lightness a pixel may sit and still be
    /// wall for the profile: the top strip of a wall is in the ceiling's
    /// shade, and darker than the rest.
    static let profileReach = 20.0

    /// Whether a pixel is the wall's own colour: near the wall's lightness
    /// and without much colour.
    static func isWallLike(_ lab: Lab, wallL: Double) -> Bool {
        abs(lab.l - wallL) < 12 && (lab.a * lab.a + lab.b * lab.b).squareRoot() < RouteScanner.groundChroma
    }

    /// Whether the band just under a line is mostly wall and the band just
    /// over it mostly not, read along the line's run.
    static func hasWallBelow(_ line: Line, bmp: Bitmap, wallL: Double) -> Bool {
        let w = bmp.width, h = bmp.height
        let x0 = Int(line.run?.lowerBound ?? 0), x1 = Int(line.run?.upperBound ?? Double(w - 1))
        guard x1 > x0 else { return false }
        var below = 0, belowAll = 0, above = 0, aboveAll = 0
        for x in stride(from: max(0, x0), through: min(w - 1, x1), by: 3) {
            guard let y = line.y(atX: Double(x)) else { continue }
            for d in bandNear...bandFar {
                let yb = Int(y) + d, ya = Int(y) - d
                if yb >= 0, yb < h { belowAll += 1; if isWallLike(bmp.lab(at: yb * w + x), wallL: wallL) { below += 1 } }
                if ya >= 0, ya < h { aboveAll += 1; if isWallLike(bmp.lab(at: ya * w + x), wallL: wallL) { above += 1 } }
            }
        }
        guard belowAll > 0, aboveAll > 0 else { return false }
        return Double(below) / Double(belowAll) >= wallBelow && Double(above) / Double(aboveAll) <= notWallAbove
    }

    /// The same seam, found again a few degrees off. Angles wrap at 180,
    /// where rho changes sign.
    private static func near(_ l: Line, theta: Double, rho: Double) -> Bool {
        var dt = abs(l.theta - theta) * 180 / .pi
        var dr = abs(l.rho - rho)
        if dt > 180 - mergeAngle { dt = 180 - dt; dr = abs(l.rho + rho) }
        return dt < mergeAngle && dr < mergeRho
    }

    /// How far past the end of an edge's run it still counts, as a share
    /// of the picture's width.
    static let runSlack = 0.03

    /// The longest continuous run of seam along the line, with small gaps
    /// allowed, as a share of the line's length inside the picture, and
    /// the x-span of that run. Nil when it is not a seam.
    static func walk(theta: Double, rho: Double, mask: [Bool], width: Int, height: Int,
                     diag: Double) -> (support: Double, run: ClosedRange<Double>)? {
        let c = cos(theta), s = sin(theta)
        let dx = -s, dy = c
        let px = rho * c, py = rho * s
        var inside = 0
        var runLength = 0, runHits = 0, gap = 0
        var runStart = 0.0
        var bestLength = 0, bestHits = 0
        var bestStart = 0.0, bestEnd = 0.0
        for t in stride(from: -diag, through: diag, by: 1.0) {
            let fx = px + t * dx
            let x = Int(fx.rounded()), y = Int((py + t * dy).rounded())
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            inside += 1
            var hit = mask[y * width + x]
            if !hit {
                for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + ox, ny = y + oy
                    if nx >= 0, ny >= 0, nx < width, ny < height, mask[ny * width + nx] { hit = true; break }
                }
            }
            if hit {
                if runLength == 0 { runHits = 0; runStart = fx }
                runLength += gap + 1; runHits += 1; gap = 0
                if runLength > bestLength { bestLength = runLength; bestHits = runHits; bestStart = runStart; bestEnd = fx }
            } else {
                gap += 1
                if gap > maximumGap { runLength = 0; gap = 0 }
            }
        }
        guard inside > 0, bestLength > 0 else { return nil }
        let density = Double(bestHits) / Double(bestLength)
        let runShare = Double(bestLength) / diag
        guard density >= minimumSupport, runShare >= minimumRun else { return nil }
        return (density, min(bestStart, bestEnd)...max(bestStart, bestEnd))
    }

    // MARK: Faces

    /// Which face a point is on: its side of every line, as a key.
    static func face(of p: CGPoint, lines: [Line], width: Int, height: Int) -> String {
        let q = CGPoint(x: p.x * Double(width), y: p.y * Double(height))
        return lines.map { $0.side(q) ? "1" : "0" }.joined()
    }

    /// The share of a route's holds a face needs before its holds are kept.
    static let homeShare = 0.2

    /// The holds that are on the route's own face, and the ones set aside.
    static func split(_ holds: [RouteScanner.Hold], lines: [Line], width: Int, height: Int)
        -> (kept: [RouteScanner.Hold], aside: [RouteScanner.Hold]) {
        guard !lines.isEmpty, holds.count >= 3 else { return (holds, []) }
        let faces = holds.map { face(of: CGPoint(x: $0.rect.midX, y: $0.rect.midY), lines: lines, width: width, height: height) }
        let counts = Dictionary(grouping: faces, by: { $0 }).mapValues(\.count)
        let home = Set(counts.filter { Double($0.value) / Double(holds.count) > homeShare }.keys)
        var kept: [RouteScanner.Hold] = [], aside: [RouteScanner.Hold] = []
        for (h, f) in zip(holds, faces) { if home.contains(f) { kept.append(h) } else { aside.append(h) } }
        return (kept, aside)
    }
}
