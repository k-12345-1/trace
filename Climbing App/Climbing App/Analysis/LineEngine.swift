import Foundation
import CoreGraphics

/// Reading a line through a scanned route.
///
/// ## What a scan actually gives us
///
/// A photograph, one color, and the boxes Trace found in that color. That is
/// the whole input. It contains no hold type, no orientation, no wall angle, no
/// depth, and no scale: nothing in the picture says whether a box is a jug or a
/// crimp, which way it faces, or how far apart two of them are in centimeters.
///
/// So this does not produce beta. Beta is a sequence of hands and feet on holds
/// whose shapes you know, and a photograph of colored blobs cannot know them.
/// What it produces is a reading of the **line**: the order the holds go in,
/// which gaps are long relative to the rest of the route, where it goes
/// sideways instead of up, and where two holds sit close enough together to
/// likely be a match rather than a move.
///
/// Every distance here is **relative to the route's own median gap**, never in
/// centimeters, because the photo has no scale and inventing one would be the
/// most convincing possible way to be wrong.
enum LineEngine {

    /// A move between two holds, and what is notable about it.
    struct Move: Identifiable {
        let index: Int
        let from: CGRect
        let to: CGRect
        /// The gap, as a multiple of this route's median gap. One is typical.
        let reach: Double
        /// How far this move goes sideways compared to how far it goes up.
        /// Above one is a move that travels across more than it climbs.
        let sideways: Double
        let kind: Kind

        var id: Int { index }

        enum Kind {
            /// Nothing stands out about it.
            case ordinary
            /// Much longer than the rest of this route.
            case long
            /// Close enough that both hands probably end up on the same hold.
            case match
            /// Travels across the wall more than up it.
            case across
        }
    }

    struct Line {
        /// Every hold, bottom to top.
        let holds: [CGRect]
        /// The saved traced outlines, aligned with `holds` when a route came
        /// from the photo scanner. Empty for callers that only have rectangles.
        let outlines: [[CGPoint]]
        /// The holds the hands go to, bottom to top, the start holds first.
        /// The route as a climber reads it: a sequence of hand moves, with
        /// the feet taking whatever is below.
        let hands: [CGRect]
        /// Holds only a foot goes to: everything below the start, and
        /// anything too small to take a hand.
        let feet: [CGRect]
        /// How many holds the start stickers named. Two is a hand on each;
        /// one is both hands matched on it; none is a start nobody marked.
        let startCount: Int
        /// The holds under the finish stickers. Empty when none were read,
        /// in which case the top hand hold is the finish.
        let finishes: [CGRect]
        let moves: [Move]
        /// The longest move on the route, which is where it is most likely to
        /// stop you. Not "the crux": a crux can be a bad hold on a short move,
        /// and a photograph cannot see a bad hold.
        let longest: Move?

        var isTraverse: Bool {
            guard !moves.isEmpty else { return false }
            return moves.filter { $0.kind == .across }.count * 2 > moves.count
        }
    }

    // MARK: Thresholds, all relative

    /// A gap this many times the route's median before it is worth pointing at.
    static let longMove = 1.6
    /// Below this, two holds are close enough to be one stance.
    static let matchMove = 0.45
    /// Sideways travel over upward travel, past which a move reads as across.
    static let acrossRatio = 1.3
    /// Fewer holds than this and there is no line to read.
    static let minimumHolds = 3
    /// A hold under this share of the route's middle hold, by area, is a
    /// foot chip: a hand does not go there. The figure used to hang off
    /// them, which is what a climber notices first.
    static let footChip = 0.3
    /// Above the start the bar is lower: a small hold up the wall is a
    /// pocket or a crimp a hand goes to, not a chip for a foot. On a V0
    /// of jugs and pockets the pockets were filed as feet and the hands
    /// skipped them. Only a hold under this share is a chip up there.
    static let tinyChip = 0.1
    /// A hold this far below the lowest start hold, in frame heights, is
    /// below the start and so for feet only.
    static let belowStart = 0.01

    // MARK: Reading it

    /// - Parameter starts: the holds the start stickers sit under, as
    ///   indices into `holds`. Empty when none were read, in which case the
    ///   start is the lowest hand-sized holds.
    static func read(holds: [CGRect], starts: [Int] = [], finishes: [Int] = [],
                     outlines: [[CGPoint]] = []) -> Line? {
        guard holds.count >= minimumHolds else { return nil }
        let ordered = order(holds)
        guard ordered.count >= minimumHolds else { return nil }
        let orderedOutlines: [[CGPoint]] = ordered.map { rect in
            guard let i = holds.firstIndex(of: rect), outlines.indices.contains(i) else { return [] }
            return outlines[i]
        }

        // Hands and feet. A start hold is a hand hold whatever its size;
        // everything below the lowest start is feet; a chip is feet.
        let startRects = starts.compactMap { holds.indices.contains($0) ? holds[$0] : nil }
        let finishRects = finishes.compactMap { holds.indices.contains($0) ? holds[$0] : nil }
        let areas = holds.map { Double($0.width * $0.height) }.sorted()
        let middle = areas[areas.count / 2]
        // The start, or without stickers the lowest hand-sized hold: what
        // lies below it is for feet, and what lies above it is mostly for
        // hands.
        let lowestStartY = startRects.map(\.midY).max()
            ?? ordered.filter { Double($0.width * $0.height) >= middle * footChip }.map(\.midY).max()
        func isHand(_ h: CGRect) -> Bool {
            if startRects.contains(h) || finishRects.contains(h) { return true }
            let area = Double(h.width * h.height)
            if let y = lowestStartY, h.midY > y + belowStart { return false }
            if area >= middle * footChip { return true }
            return lowestStartY != nil && area >= middle * tinyChip
        }
        var hands = ordered.filter(isHand)
        let feet = ordered.filter { !isHand($0) }
        // The start holds come first, however the ordering placed them.
        if !startRects.isEmpty {
            hands = startRects.sorted { $0.midX < $1.midX } + hands.filter { !startRects.contains($0) }
        }
        guard hands.count >= 2 else { return nil }

        var gaps: [Double] = []
        for (a, b) in zip(hands, hands.dropFirst()) {
            gaps.append(distance(a, b))
        }
        let median = medianOf(gaps)
        guard median > 0 else { return nil }

        var moves: [Move] = []
        for (i, gap) in gaps.enumerated() {
            let a = hands[i], b = hands[i + 1]
            let across = abs(b.midX - a.midX)
            let up = abs(b.midY - a.midY)
            let sideways = up > 0.0001 ? across / up : .infinity
            let reach = gap / median

            let kind: Move.Kind
            if reach <= matchMove { kind = .match }
            else if reach >= longMove { kind = .long }
            else if sideways >= acrossRatio { kind = .across }
            else { kind = .ordinary }

            moves.append(Move(index: i, from: a, to: b,
                              reach: reach, sideways: sideways, kind: kind))
        }

        return Line(holds: ordered, outlines: orderedOutlines, hands: hands, feet: feet,
                    startCount: startRects.count, finishes: finishRects, moves: moves,
                    longest: moves.max { $0.reach < $1.reach })
    }

    /// The order the holds are met: bottom to top, always.
    ///
    /// Height is the primary rule and it is not negotiable. A line up a wall
    /// goes up, so an ordering that ever descends is wrong about the route, and
    /// a greedy nearest-neighbor walk does exactly that: it takes the cheap
    /// hops first, strands the ones it skipped, and then has to double back
    /// down to collect them.
    ///
    /// Proximity decides only between holds at the **same** height, where
    /// height genuinely cannot separate them. Two holds count as the same
    /// height when they sit within a quarter of the route's average vertical
    /// step of each other, and within such a band the nearer one to where you
    /// already are comes first.
    ///
    /// This is still a reading and not the setter's sequence. It is the order a
    /// line has to go in if it goes up.
    static func order(_ holds: [CGRect]) -> [CGRect] {
        guard holds.count > 1 else { return holds }
        let byHeight = holds.sorted { $0.midY > $1.midY }   // origin top left

        let top = byHeight.last!.midY, bottom = byHeight.first!.midY
        let step = (bottom - top) / Double(holds.count - 1)
        let band = max(step * 0.25, 1e-6)

        var out: [CGRect] = []
        var i = 0
        while i < byHeight.count {
            // Everything level with byHeight[i].
            var j = i + 1
            while j < byHeight.count, byHeight[i].midY - byHeight[j].midY <= band { j += 1 }

            var level = Array(byHeight[i..<j])
            if level.count == 1 {
                out.append(level[0])
            } else {
                // Nearest first, walking from wherever the line already is.
                var here = out.last
                while !level.isEmpty {
                    let next: CGRect
                    if let here {
                        next = level.min { distance(here, $0) < distance(here, $1) }!
                    } else {
                        next = level.first!
                    }
                    out.append(next)
                    level.removeAll { $0 == next }
                    here = next
                }
            }
            i = j
        }
        return out
    }

    // MARK: Saying it

    /// The line in one sentence, or nil when there is nothing worth saying.
    static func summary(_ line: Line) -> String? {
        guard !line.moves.isEmpty else { return nil }
        let holds = line.holds.count
        var parts = [line.feet.isEmpty ? "\(holds) holds" : "\(holds) holds, \(line.hands.count) for the hands"]

        if line.isTraverse {
            parts.append("mostly across rather than up")
        }
        let longs = line.moves.filter { $0.kind == .long }.count
        if longs == 1 {
            parts.append("one move noticeably longer than the rest")
        } else if longs > 1 {
            parts.append("\(longs) moves noticeably longer than the rest")
        }
        let matches = line.moves.filter { $0.kind == .match }.count
        if matches > 0 {
            parts.append("\(matches) pair\(matches == 1 ? "" : "s") close enough to share")
        }
        return parts.joined(separator: ", ") + "."
    }

    static func note(for move: Move) -> String? {
        switch move.kind {
        case .long:
            return String(format: "Move %d is the long one, about %.1f times the average gap on this route. Expect to need a high foot or a hip turned in before it, or to throw for it.", move.index + 1, move.reach)
        case .across:
            return "Move \(move.index + 1) travels sideways more than it climbs. Moves like that are where your weight ends up outside your hands and feet, which is what turns into a swing."
        case .match:
            return "Holds \(move.index + 1) and \(move.index + 2) are close enough that both hands probably end up on the same one."
        case .ordinary:
            return nil
        }
    }

    /// The route as a sequence, one line per move, each with a cue for the
    /// move's shape. This replaced a note per remarkable move, which said the
    /// same paragraph about swinging for every sideways move on a traverse
    /// and nothing at all about the ones in between, so a climber reading it
    /// could not tell where they were in the route.
    ///
    /// Move n goes from hold n to hold n + 1. Ordinary moves get their
    /// direction and nothing more; the coaches' cues are given once each,
    /// on the first move of that kind, and later moves of the same kind
    /// only name it.
    static func sequence(_ line: Line) -> [String] {
        var out: [String] = []
        var said: Set<String> = []
        for m in line.moves {
            let n = m.index + 1
            let dir = direction(of: m)
            switch m.kind {
            case .match:
                out.append("\(n) to \(n + 1): close together. Match hands on one, then move on.")
            case .long:
                let first = said.insert("long").inserted
                out.append(first
                    ? String(format: "%d to %d: the long one, %.1f times the usual gap. Get a foot high or turn a hip in before it, or throw for it.", n, n + 1, m.reach)
                    : "\(n) to \(n + 1): long again.")
            case .across:
                let first = said.insert("across").inserted
                out.append(first
                    ? "\(n) to \(n + 1): \(dir), more across than up. Flag the trailing foot or keep a hip turned in so your weight stays between your hands."
                    : "\(n) to \(n + 1): \(dir), across.")
            case .ordinary:
                out.append("\(n) to \(n + 1): \(dir).")
            }
        }
        return out
    }

    /// Up, left, right, or a mix, from the photograph's point of view.
    private static func direction(of m: Move) -> String {
        let dx = m.to.midX - m.from.midX
        let dy = m.from.midY - m.to.midY   // y grows downward
        let side = dx > 0 ? "right" : "left"
        if abs(dx) < abs(dy) * 0.35 { return dy >= 0 ? "straight up" : "down" }
        if abs(dy) < abs(dx) * 0.35 { return "\(side)" }
        return dy >= 0 ? "up and \(side)" : "down and \(side)"
    }

    /// The caveat, shown wherever a line is.
    static let caveat = "Read from the shape of the holds in your photo, and nothing else. Trace cannot see which way a hold faces, how good it is, or how steep the wall is, so this is the line rather than the beta."

    // MARK: Geometry

    static func distance(_ a: CGRect, _ b: CGRect) -> Double {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        return (dx * dx + dy * dy).squareRoot()
    }

    static func medianOf(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
