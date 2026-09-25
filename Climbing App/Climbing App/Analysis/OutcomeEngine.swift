import Foundation
import CoreGraphics

/// Did the climb end at the top, or on the mat?
///
/// What this can and cannot know, said once here so no screen has to imply more.
///
/// Trace has never seen the route. It does not know where the finish hold is,
/// how high the wall goes, or what the setter called the top. All it has is
/// where your center of mass went. So "topped" here means one specific,
/// checkable thing: you reached the highest point of the climb and held still
/// there. On a boulder that is what matching the finish looks like, which is why
/// it is good enough to mark a send, and it is also why a send Trace works out
/// for itself is one you can take back with one tap.
///
/// A fall is the opposite signature and a much cleaner one. Coming off the wall
/// is the one thing in climbing that is not under your control: the body drops
/// at close to g, and nothing a climber does on purpose looks like that.
enum OutcomeEngine {

    /// How the attempt ended.
    enum Outcome: Equatable {
        /// Reached the high point and held it.
        case topped(at: Double)
        /// Left the wall. `at` is when the drop began; `rise` is how far the
        /// center of mass had climbed by then, in torso lengths, which is the
        /// only height scale available without knowing the wall.
        case fell(at: Double, rise: Double)
        /// Neither signature is present. A clip that was cut early, or a
        /// traverse, or tracking too poor to say.
        case unclear
    }

    // MARK: Thresholds
    //
    // All distances are in torso lengths, which is the only scale available
    // without knowing how far the phone was from the wall.

    /// Still enough to count as holding a position.
    static let holdRadius = 0.18
    /// For this long, from the high point.
    static let holdSeconds = 0.45
    /// A drop of this much, in torso lengths.
    static let fallDrop = 1.1
    /// Within this long. Free fall covers about 1.2 m in half a second, which is
    /// somewhere over two torso lengths, so this is comfortably short of the
    /// worst case and well clear of a controlled downclimb.
    static let fallWindow = 0.5
    /// A fall starts at the top. A drop that begins long after the high point is
    /// someone climbing down, or jumping off after they finished.
    static let fallStartsWithin = 0.4
    /// Below this the climb never went anywhere, and neither reading applies.
    static let minimumRise = 0.6

    // MARK: The reading

    static func outcome(frames: [PoseFrame]) -> Outcome {
        let usable = frames.filter { $0.com != nil }
        guard usable.count >= 8 else { return .unclear }
        guard let torso = MetricsEngine.medianTorso(usable), torso > 0.01 else { return .unclear }

        let ys = usable.map { $0.com!.y }          // origin top left, so less is higher
        guard let lowest = ys.max(), let highest = ys.min() else { return .unclear }
        let rise = (lowest - highest) / torso
        guard rise >= minimumRise else { return .unclear }

        guard let peak = ys.firstIndex(of: highest) else { return .unclear }
        let peakTime = usable[peak].time

        // Held at the top.
        let held = usable[peak...].prefix { $0.time - peakTime <= holdSeconds }
        if let last = held.last, last.time - peakTime >= holdSeconds * 0.8 {
            let strayed = held.contains { abs($0.com!.y - highest) / torso > holdRadius }
            if !strayed { return .topped(at: peakTime) }
        }

        // Came off it.
        for i in peak..<usable.count {
            let start = usable[i]
            guard start.time - peakTime <= fallStartsWithin else { break }
            let after = usable[i...].prefix { $0.time - start.time <= fallWindow }
            guard let end = after.max(by: { $0.com!.y < $1.com!.y }) else { continue }
            let drop = (end.com!.y - start.com!.y) / torso
            if drop >= fallDrop {
                // The fall is from the high point, so the height reached is the
                // whole rise of the climb.
                return .fell(at: start.time, rise: rise)
            }
        }

        return .unclear
    }

    /// Where it went wrong, in the moment before it did.
    ///
    /// Not a new judgement. This reaches for the finding that was already open
    /// when the climber came off, because a leak that shows up in the two
    /// seconds before a fall is the one worth naming; inventing a separate
    /// explanation of a fall would be a claim about a route Trace cannot see.
    static let lookBack = 2.0

    static func cause(of outcome: Outcome, findings: [Finding]) -> Finding? {
        guard case .fell(let when, _) = outcome else { return nil }
        let open = findings.filter { $0.start <= when && $0.end >= when - lookBack }
        return open.max { $0.severity < $1.severity }
    }
}
