import Foundation
import CoreGraphics

/// How directly you got from each position to the next one.
///
/// ## Why the straight line had to go
///
/// The measure this replaces compared the whole path against a straight line
/// from the start of the climb to the top of it. On a boulder that line does
/// not exist. The holds are where the setter put them, the sequence goes where
/// they go, and a climber who followed a diagonal problem perfectly would still
/// be told they travelled twice as far as they needed to. It was measuring the
/// route and reporting it as the climbing.
///
/// ## What is measured instead
///
/// A climb is a series of positions with movement between them. Between any two
/// consecutive positions there is a shortest path, which is the straight line
/// from one to the other, and unlike a line up the middle of the wall that one
/// is reachable: both of its ends are places the climber actually was. Anything
/// travelled beyond it is a detour they took rather than a shape the route
/// forced on them.
///
/// So a diagonal traverse climbed cleanly scores as well as a vertical ladder
/// climbed cleanly, which is the point. What still scores badly is what should:
/// reaching, missing, and coming back; swinging out and hauling in; drifting
/// past a hold and correcting.
///
/// ## Where the positions come from
///
/// Not from an absolute idea of stillness. A threshold in units per second
/// says a fluid climber never stopped and therefore made one enormous move,
/// which hands the best climbers the worst reading. The boundaries here are
/// local minima of the climber's own speed, judged against their own median, so
/// the question is "when was this climber slowest" rather than "when were they
/// slower than some number".
enum MoveEngine {

    /// One position to the next.
    struct Move {
        let start: Double
        let end: Double
        let from: CGPoint
        let to: CGPoint
        /// Path length actually covered.
        let travelled: Double
        /// The straight line between the two ends of it.
        let direct: Double

        var waste: Double { max(0, travelled - direct) }
        /// One is a straight hop; zero is all detour.
        var directness: Double { travelled > 1e-6 ? min(1, direct / travelled) : 1 }
    }

    struct Reading {
        let moves: [Move]
        let travelled: Double
        let direct: Double

        /// The share of everything travelled that was not toward the next
        /// position. This is the number the grade and the finding both use.
        var waste: Double { travelled > 1e-6 ? max(0, travelled - direct) / travelled : 0 }
    }

    // MARK: The judgements

    /// A boundary has to be slower than this share of the climber's own median
    /// speed. Relative rather than absolute, so it means the same thing for a
    /// climber who never stops and one who rests on every hold.
    static let restFraction = 0.55
    /// Two boundaries closer together than this are the same moment.
    static let minimumGap = 0.30
    /// A move shorter than this went nowhere, and dividing by it says nothing.
    /// In torso lengths, so it does not depend on how far away the phone was.
    static let minimumMove = 0.35
    /// Fewer moves than this is not a climb with a shape to it.
    static let minimumMoves = 3

    // MARK: Reading

    static func read(frames: [PoseFrame]) -> Reading? {
        let usable = frames.filter { $0.com != nil }
        guard usable.count >= 8 else { return nil }
        guard let torso = MetricsEngine.medianTorso(usable), torso > 0.01 else { return nil }

        let path = usable.map { $0.com! }
        let times = usable.map(\.time)
        let bounds = boundaries(path: path, times: times)
        guard bounds.count >= minimumMoves + 1 else { return nil }

        var moves: [Move] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            guard b > a else { continue }
            var travelled = 0.0
            for i in a..<b { travelled += distance(path[i], path[i + 1]) }
            let direct = distance(path[a], path[b])
            // A move that went nowhere is the climber shifting their weight,
            // not a move, and its directness is a ratio of two noise floors.
            guard travelled / torso >= minimumMove else { continue }
            moves.append(Move(start: times[a], end: times[b],
                              from: path[a], to: path[b],
                              travelled: travelled, direct: direct))
        }
        guard moves.count >= minimumMoves else { return nil }

        return Reading(moves: moves,
                       travelled: moves.reduce(0) { $0 + $1.travelled },
                       direct: moves.reduce(0) { $0 + $1.direct })
    }

    /// Indices into the path where the climber was between moves.
    ///
    /// Always includes both ends, because the start of the climb and the top of
    /// it are positions whatever the speed was doing there.
    static func boundaries(path: [CGPoint], times: [Double]) -> [Int] {
        let speeds = MetricsEngine.speedSeries(path: path, times: times)
        guard speeds.count == path.count, path.count >= 3 else { return [] }

        // The climber's own speed while moving, not their average including
        // rests.
        //
        // A plain median over every frame is dragged to zero by a long rest:
        // ninety still frames in a two hundred frame clip and the median IS
        // zero, so nothing is slower than a fraction of it, no boundaries are
        // found, and the climb has no moves in it at all. The climbers that
        // silently disabled were the ones who rest, which is to say the ones
        // with the most to learn from being told about it.
        let sorted = speeds.sorted()
        let high = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        let moving = speeds.filter { $0 > high * 0.05 }.sorted()
        let median = moving.isEmpty ? sorted[sorted.count / 2] : moving[moving.count / 2]
        guard median > 1e-6 else { return [] }
        let ceiling = median * restFraction

        var out = [0]
        for i in 1..<(speeds.count - 1) {
            guard speeds[i] <= ceiling,
                  speeds[i] <= speeds[i - 1], speeds[i] <= speeds[i + 1]
            else { continue }
            if let last = out.last, times[i] - times[last] < minimumGap { continue }
            out.append(i)
        }
        let end = path.count - 1
        if let last = out.last, times[end] - times[last] < minimumGap, out.count > 1 {
            out.removeLast()
        }
        out.append(end)
        return out
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
