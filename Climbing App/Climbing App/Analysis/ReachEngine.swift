import Foundation
import CoreGraphics

/// Each hand move, and how much of it the body did.
///
/// ## The question this answers
///
/// "Keep your hips close to the wall" and "drop your knee" are true and useless,
/// because they are said about climbing rather than about a move. The useful
/// version is: on *this* reach, at *this* second, your body was arranged so that
/// your arm had to do the work, and on *that* one it was arranged so that it did
/// not. Trace can see the difference, and a climber can go and look at both.
///
/// ## What is actually measured
///
/// A reach moves a hand from one hold to another. That distance is covered by
/// two things: the body travelling, and the arm extending. Project the reaching
/// shoulder's travel onto the direction the hand went and you have the share
/// the body delivered. It needs no depth, no wall, and no idea of where the
/// holds are, which matters because a phone on the floor of a gym has none of
/// those.
///
/// One is not simply better than the other. A lock-off is an arm move on
/// purpose, and a climber who never extends an arm is not climbing well. What
/// the spread says is where the effort went, and the spread within one climb is
/// large: on the first real clip Trace was shown, the same climber carried 7% of
/// one reach with their body and 119% of another. That is the same person on the
/// same problem thirty seconds apart, which is why it is worth showing.
///
/// ## What is deliberately not claimed
///
/// Whether a turned hip caused the difference. `hipOpenness` is recorded because
/// it is the thing a coach would point at, and on that first clip the turned-hip
/// moves were carried by the body more often than the square ones, at r = -0.48
/// across nine reaches. Nine reaches on one climb is an observation and not a
/// finding, so the reading reports both numbers and lets the climber look, and
/// says nothing about which caused which.
enum ReachEngine {

    /// One hand, moving from one hold to the next.
    struct Reach: Identifiable {
        let hand: JointID
        /// When it set off and when it settled.
        let start: Double
        let end: Double
        /// How far the hand went, in torso lengths.
        let travelled: Double
        /// How far the reaching shoulder went along that same direction, in
        /// torso lengths. Negative means the shoulder moved the other way.
        let carried: Double
        /// The shoulder's travel as a share of the hand's. Above 1 means the
        /// body moved further than the hand did and the arm folded.
        let share: Double
        /// The reaching arm's elbow angle at the catch, in degrees.
        let catchElbow: Double?
        /// Hip width at launch against this climber's own widest, so 1.0 is
        /// square to the camera and 0.4 is well turned. Nil when the hips were
        /// not visible.
        let hipOpenness: Double?

        var id: Double { start }
        var isLeft: Bool { hand == .leftWrist }
        var handName: String { isLeft ? "left hand" : "right hand" }
        /// The same, starting a sentence.
        var handTitle: String { isLeft ? "Left hand" : "Right hand" }

        var timecode: String {
            let m = Int(start) / 60, s = Int(start) % 60
            return String(format: "%d:%02d", m, s)
        }

        /// Where to put the playhead to watch it: just before it sets off.
        var lookAt: Double { max(0, start - 0.3) }
    }

    struct Reading {
        let reaches: [Reach]

        /// The one the body did most of, and the one the arm did most of. Both
        /// are this climber's own, on this climb: the comparison is between two
        /// moments a person can watch back, not against a number from anywhere
        /// else.
        var bodyLed: Reach? { reaches.max { $0.share < $1.share } }
        var armLed: Reach? { reaches.min { $0.share < $1.share } }

        var medianShare: Double {
            guard !reaches.isEmpty else { return 0 }
            let s = reaches.map(\.share).sorted()
            return s[s.count / 2]
        }

        /// Worth showing only when there is a difference to show.
        var spread: Double { (bodyLed?.share ?? 0) - (armLed?.share ?? 0) }
    }

    // MARK: The judgements

    /// A hand going faster than this has been thrown rather than adjusted, in
    /// torso lengths per second. `MetricsEngine.reachTorsoPerSecond`.
    static var throwSpeed: Double { MetricsEngine.reachTorsoPerSecond }
    /// And it has landed when it drops below this and stays there. Two
    /// thresholds rather than one, because a single threshold is crossed several
    /// times during one throw: the shipped detector found thirty-six reaches in
    /// a thirty-second climb that contains nine, six of them inside half a
    /// second of each other.
    static let settleSpeed = 0.45
    /// How long it has to stay settled before the hand is on something.
    static let settleSeconds = 0.20
    /// A hand that ended up less than this from where it set off was adjusted on
    /// the hold, not moved to another one. In torso lengths, and the app's
    /// existing number for the same idea rather than a second one: on the real
    /// climb the count is nine anywhere between 0.3 and 0.7, so the settle is
    /// what separates a reach from an adjustment and this floor only has to
    /// exclude a hand that went nowhere at all.
    static var minimumTravel: Double { MetricsEngine.reachTorsoDistance }
    /// Fewer reaches than this is not a climb with a pattern in it.
    static let minimumReaches = 3
    /// The two ends have to be this far apart in share before they are two
    /// different things rather than two numbers. A climb where every reach was
    /// made the same way has nothing to compare, and picking a best and a worst
    /// out of nine numbers a few points apart is picking noise.
    static let worthShowing = 0.35
    /// And the hips are only mentioned when they differ by more than the
    /// measure's own slop.
    static let hipDifferenceWorthNaming = 0.15
    /// An elbow angle below this is the tracker confusing a wrist with an
    /// elbow rather than an arm folded double, so it is not reported.
    static let plausibleElbow = 35.0

    static let caveat = "Neither is a mistake. A lock-off is an arm move on purpose, and a climber who never extends an arm is not climbing. This says where the effort went on each one."

    // MARK: Reading

    static func read(frames: [PoseFrame]) -> Reading? {
        let usable = frames.filter { $0.com != nil }
        guard usable.count >= 8,
              let torso = MetricsEngine.medianTorso(usable), torso > 0.01
        else { return nil }

        let square = squareHipWidth(usable)
        var out: [Reach] = []
        for hand in [JointID.leftWrist, JointID.rightWrist] {
            out += reaches(of: hand, in: usable, torso: torso, square: square)
        }
        out.sort { $0.start < $1.start }
        guard out.count >= minimumReaches else { return nil }
        return Reading(reaches: out)
    }

    /// The moments a hand was thrown somewhere new and settled there.
    ///
    /// Shared with `MetricsEngine.handContacts`, so the app has one idea of what
    /// a hand move is rather than two that disagree.
    static func settles(of hand: JointID, in frames: [PoseFrame], torso: Double) -> [(from: Int, to: Int)] {
        let times = frames.map(\.time)
        let speeds = jointSpeeds(of: hand, in: frames, times: times, torso: torso)
        var out: [(from: Int, to: Int)] = []
        var moving = false
        var launch = 0
        var quiet: Int?

        for i in frames.indices {
            guard i < speeds.count, frames[i].pt(hand) != nil else { continue }
            if !moving {
                if speeds[i] > throwSpeed { moving = true; launch = max(0, i - 1); quiet = nil }
                continue
            }
            if speeds[i] < settleSpeed {
                // The hand landed when it stopped, not when it had been stopped
                // for long enough to be sure. The window confirms the landing;
                // reporting its far end puts every contact `settleSeconds` late,
                // which on a deadpoint is the whole measurement.
                if quiet == nil { quiet = i }
                if let q = quiet, times[i] - times[q] >= settleSeconds {
                    if let landed = frames[q].pt(hand), let origin = frames[launch].pt(hand),
                       hypot(Double(landed.x - origin.x), Double(landed.y - origin.y)) / torso
                        >= minimumTravel {
                        out.append((launch, q))
                    }
                    moving = false
                    quiet = nil
                }
            } else {
                quiet = nil
            }
        }
        return out
    }

    private static func reaches(of hand: JointID, in frames: [PoseFrame],
                                torso: Double, square: Double?) -> [Reach] {
        let shoulder: JointID = hand == .leftWrist ? .leftShoulder : .rightShoulder
        let elbow: JointID = hand == .leftWrist ? .leftElbow : .rightElbow

        return settles(of: hand, in: frames, torso: torso).compactMap { span in
            let a = frames[span.from], b = frames[span.to]
            guard let w0 = a.pt(hand), let w1 = b.pt(hand),
                  let s0 = a.pt(shoulder), let s1 = b.pt(shoulder) else { return nil }

            let dx = Double(w1.x - w0.x), dy = Double(w1.y - w0.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance > 1e-6 else { return nil }
            let travelled = distance / torso

            // The shoulder's travel projected onto the hand's direction.
            let carried = (Double(s1.x - s0.x) * (dx / distance)
                           + Double(s1.y - s0.y) * (dy / distance)) / torso

            return Reach(hand: hand,
                         start: a.time, end: b.time,
                         travelled: travelled,
                         carried: carried,
                         share: carried / travelled,
                         catchElbow: angle(of: b, shoulder, elbow, hand)
                            .flatMap { $0 >= plausibleElbow ? $0 : nil },
                         hipOpenness: openness(of: a, square: square))
        }
    }

    // MARK: Hips

    /// The climber's own square-on hip width: the widest their hips appear over
    /// the climb, at the 95th percentile so one bad frame does not set it.
    ///
    /// Self-calibrated because the quantity is a projection. Hips that turn away
    /// from the camera narrow, but so do hips seen from further away, and the
    /// only reference that survives both is the same climber's widest moment in
    /// the same clip. Ground frames are not excluded: standing at the bottom of
    /// the route facing the wall is exactly the square-on reading wanted.
    static func squareHipWidth(_ frames: [PoseFrame]) -> Double? {
        let widths = frames.compactMap { f -> Double? in
            guard let l = f.pt(.leftHip), let r = f.pt(.rightHip) else { return nil }
            return abs(Double(l.x - r.x))
        }.sorted()
        guard widths.count >= 10 else { return nil }
        let w = widths[min(widths.count - 1, Int(Double(widths.count) * 0.95))]
        return w > 1e-6 ? w : nil
    }

    private static func openness(of frame: PoseFrame, square: Double?) -> Double? {
        guard let square,
              let l = frame.pt(.leftHip), let r = frame.pt(.rightHip) else { return nil }
        return min(1, abs(Double(l.x - r.x)) / square)
    }

    // MARK: Helpers

    private static func angle(of frame: PoseFrame, _ a: JointID, _ b: JointID, _ c: JointID) -> Double? {
        guard let p = frame.pt(a), let q = frame.pt(b), let s = frame.pt(c) else { return nil }
        return MetricsEngine.angle(at: q, from: p, to: s)
    }

    private static func jointSpeeds(of joint: JointID, in frames: [PoseFrame],
                                    times: [Double], torso: Double) -> [Double] {
        var out: [Double] = [0]
        for i in 1..<frames.count {
            guard let a = frames[i - 1].pt(joint), let b = frames[i].pt(joint) else {
                out.append(0)
                continue
            }
            let dt = max(times[i] - times[i - 1], 0.0005)
            out.append(hypot(Double(a.x - b.x), Double(a.y - b.y)) / dt / torso)
        }
        return out
    }
}
