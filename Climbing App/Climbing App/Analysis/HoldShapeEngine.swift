import Foundation
import CoreGraphics

/// A rough guess at what a hold is, from how it looks in the scan.
///
/// A phone photograph of a wall gives a few hundred pixels per hold, which is
/// enough to see that a hold is big or small, long or round, and whether it
/// has a lit top face over a shadowed lip or shades off smoothly. It is not
/// enough to see a pocket, which is a hole, or a volume, which is wall
/// coloured and not scanned at all. So the guess is only ever between jugs,
/// crimps, slopers and pinches, it is offered to the climber as a suggestion
/// rather than written as a fact, and what they say back moves the guess.
///
/// Four numbers per hold:
/// - size, the log of its area against the middle hold on the same wall,
///   so a big hold is big for this wall rather than for this photo;
/// - stretch, the longer side over the shorter, signed so that wide is
///   positive and tall is negative;
/// - lip, how much brighter the top of the hold is than the bottom, against
///   the hold's own range. A jug catches light on top and throws a shadow
///   under its lip. A sloper shades off gently;
/// - fill, how much of its box the hold's colour actually covers. Round
///   things fill their box; lumpy and angular things do not.
///
/// Each type is a prototype in that space and a hold is whichever prototype
/// it is nearest. The prototypes start where a climber would put them and are
/// then nudged by every correction, so the guess becomes this climber's own
/// over time. That is the whole of the learning and it is meant to be: a
/// classifier trained on nothing would be a worse guess dressed up better.
enum HoldShapeEngine {

    struct Features: Codable, Equatable {
        var size: Double
        var stretch: Double
        var lip: Double
        var fill: Double

        var vector: [Double] { [size, stretch, lip, fill] }
        /// Each axis scaled so a step along it means about as much as a step
        /// along the others.
        /// Size counts double. On the real wall a wide rail read as a crimp
        /// because its stretch outweighed its size, and a crimp is small
        /// before it is anything else. Fill counts least: the colour mask
        /// fills a box of a flat-lit hold almost completely, so it says more
        /// about the light than the shape.
        static let scale: [Double] = [2.0, 1.0, 2.5, 1.0]
        func distance(to other: Features) -> Double {
            zip(zip(vector, other.vector), Self.scale)
                .reduce(0) { $0 + pow(($1.0.0 - $1.0.1) * $1.1, 2) }
                .squareRoot()
        }
    }

    typealias HoldType = ClimbNotes.HoldType
    static let guessable: [HoldType] = [.jugs, .crimps, .slopers, .pinches]

    /// Where each type sits before anyone has corrected anything.
    static let defaultPrototypes: [HoldType: Features] = [
        .jugs:    Features(size: 0.6,  stretch: 0.2,  lip: 0.35, fill: 0.62),
        .crimps:  Features(size: -1.1, stretch: 0.5,  lip: 0.15, fill: 0.70),
        .slopers: Features(size: 0.8,  stretch: 0.0,  lip: 0.05, fill: 0.78),
        .pinches: Features(size: -0.1, stretch: -0.6, lip: 0.10, fill: 0.60)
    ]

    // MARK: Measuring

    /// How close a pixel has to be to the route's colour to be the hold rather
    /// than the wall behind it. The scanner's own tolerance.
    static let colourTolerance = 30.0

    /// The four numbers for every hold, in the order given. Nil for a hold
    /// whose box held no pixels of the colour, which happens when the box is
    /// a shadow the scanner mistook.
    static func features(of holds: [CGRect], colour: Lab, in image: CGImage) -> [Features?] {
        guard let bmp = Bitmap(image, targetWidth: RouteScanner.workingWidth) else {
            return holds.map { _ in nil }
        }
        let areas = holds.map { Double($0.width * $0.height) }.filter { $0 > 0 }.sorted()
        let middle = areas.isEmpty ? 1 : areas[areas.count / 2]
        return holds.map { rect in
            measure(rect, middleArea: middle, colour: colour, in: bmp)
        }
    }

    static func measure(_ rect: CGRect, middleArea: Double, colour: Lab, in bmp: Bitmap) -> Features? {
        let x0 = max(0, Int(rect.minX * Double(bmp.width)))
        let x1 = min(bmp.width - 1, Int(rect.maxX * Double(bmp.width)))
        let y0 = max(0, Int(rect.minY * Double(bmp.height)))
        let y1 = min(bmp.height - 1, Int(rect.maxY * Double(bmp.height)))
        guard x1 > x0, y1 > y0 else { return nil }

        var inside = 0, total = 0
        var top: [Double] = [], bottom: [Double] = [], all: [Double] = []
        let third = max(1, (y1 - y0 + 1) / 3)
        for y in y0...y1 {
            for x in x0...x1 {
                total += 1
                let lab = bmp.lab(at: y * bmp.width + x)
                guard lab.shadeDistance(to: colour) <= colourTolerance else { continue }
                inside += 1
                all.append(lab.l)
                if y < y0 + third { top.append(lab.l) }
                else if y > y1 - third { bottom.append(lab.l) }
            }
        }
        guard inside >= 6, let lo = all.min(), let hi = all.max() else { return nil }
        let range = max(hi - lo, 8)
        let lip = (mean(top) - mean(bottom)) / range
        let w = Double(rect.width), h = Double(rect.height)
        let stretch = w >= h ? (w / max(h, 0.0001) - 1) : -(h / max(w, 0.0001) - 1)
        return Features(
            size: log(max(w * h, 1e-6) / middleArea),
            stretch: max(-2, min(2, stretch)),
            lip: max(-1, min(1, lip)),
            fill: Double(inside) / Double(total))
    }

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    // MARK: Guessing

    static func classify(_ f: Features, prototypes: [HoldType: Features],
                         prior: [HoldType: Double] = [:]) -> HoldType {
        guessable.min {
            prototypes[$0]!.distance(to: f) * (prior[$0] ?? 1) < prototypes[$1]!.distance(to: f) * (prior[$1] ?? 1)
        }!
    }

    /// What the grade says before the shapes do. An easy boulder is set on
    /// jugs: a V0 of jugs and pockets read as crimps and slopers from its
    /// outlines alone, which a climber standing under it would never say.
    /// Returns a multiplier on each type's distance; under one favours it.
    static func prior(for grade: Grade?) -> [HoldType: Double] {
        guard let grade, grade.scale == .vScale else { return [:] }
        // V0 is index 3, V1 is 6.
        if grade.index <= 6 { return [.jugs: 0.6, .crimps: 1.3, .slopers: 1.2] }
        if grade.index <= 9 { return [.jugs: 0.85] }
        return [:]
    }

    struct Guess: Equatable {
        /// How many holds of each type.
        let counts: [HoldType: Int]
        var total: Int { counts.values.reduce(0, +) }
        /// The types that make up enough of the route to be worth tagging.
        var suggested: Set<HoldType> {
            guard total > 0 else { return [] }
            return Set(counts.filter { Double($0.value) / Double(total) >= HoldShapeEngine.worthTagging }.keys)
        }
        /// "Mostly crimps, some slopers", or nil when nothing could be read.
        var sentence: String? {
            guard total > 0 else { return nil }
            let ordered = counts.filter { $0.value > 0 }.sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
            }
            guard let first = ordered.first else { return nil }
            let share = Double(first.value) / Double(total)
            var out = (share >= 0.6 ? "Mostly " : "Looks like ") + first.key.rawValue
            let rest = ordered.dropFirst().filter { Double($0.value) / Double(total) >= HoldShapeEngine.worthTagging }
            if !rest.isEmpty { out += ", some " + rest.map(\.key.rawValue).joined(separator: " and ") }
            return out
        }
    }

    /// A type has to be this share of the holds before it is suggested.
    static let worthTagging = 0.25

    static func guess(_ features: [Features?], prototypes: [HoldType: Features],
                      grade: Grade? = nil) -> Guess {
        var counts: [HoldType: Int] = [:]
        let prior = prior(for: grade)
        for f in features.compactMap({ $0 }) { counts[classify(f, prototypes: prototypes, prior: prior), default: 0] += 1 }
        return Guess(counts: counts)
    }

    // MARK: Learning from the climber

    /// How far a prototype moves on one correction. Small, so one odd route
    /// cannot drag a type across the space, and a dozen agreeing ones can.
    static let step = 0.12

    /// The climber's tags against the guess, applied to the prototypes.
    ///
    /// A hold guessed as a type the climber kept pulls that type toward it, so
    /// agreement firms the guess up. A hold guessed as a type the climber
    /// dropped pushes that type away from it, and, when the climber named
    /// exactly one guessable type in its place, pulls that one toward it. With
    /// two or more named there is no saying which this hold was, so it only
    /// pushes. Tags that cannot be guessed, pockets and volumes, are left out.
    static func learn(from features: [Features?], chosen: Set<HoldType>,
                      prototypes: inout [HoldType: Features]) {
        let named = chosen.filter { guessable.contains($0) }
        let replacement: HoldType? = named.count == 1 ? named.first : nil
        for f in features.compactMap({ $0 }) {
            let guessed = classify(f, prototypes: prototypes)
            if chosen.contains(guessed) {
                move(&prototypes[guessed]!, toward: f, by: step)
            } else {
                move(&prototypes[guessed]!, toward: f, by: -step * 0.5)
                if let r = replacement, r != guessed { move(&prototypes[r]!, toward: f, by: step) }
            }
        }
    }

    private static func move(_ p: inout Features, toward f: Features, by k: Double) {
        p.size    += (f.size - p.size) * k
        p.stretch += (f.stretch - p.stretch) * k
        p.lip     += (f.lip - p.lip) * k
        p.fill    += (f.fill - p.fill) * k
    }
}
