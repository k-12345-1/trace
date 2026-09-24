import Foundation
import CoreGraphics

/// Turning pixels into metres.
///
/// A single camera cannot measure distance. What it can do, once you have said
/// how tall you are, is work backwards: find the frame where you were most
/// extended, assume that frame shows very nearly your full length, and use the
/// height of the tracked joints in that frame as the ruler.
///
/// The assumption is stated rather than hidden, because it is the whole method.
/// It holds on a boulder, where a climber reaches full extension at least once,
/// and it fails on a clip where they stay curled up. Everything it produces is
/// therefore an estimate, and the app says so.
///
/// One thing it does not spoil: a scale error is a single multiplier applied to
/// every frame equally, so attempt-against-attempt comparison survives it intact.
enum BodyScale {

    /// Nose to ankle, as a fraction of standing height.
    ///
    /// Vision's topmost reliable joint is the nose and its lowest is the ankle,
    /// so the tracked body is shorter than the person. Ankle height is about 4%
    /// of stature and the nose sits at about 93%, which leaves 89% between them.
    /// Dempster and the anthropometric tables that follow him agree closely
    /// enough that a single constant is honest here.
    static let noseToAnkleFraction = 0.89

    /// Metres per unit of normalised image height, or nil when there is nothing
    /// to work from.
    static func metresPerUnit(frames: [PoseFrame], body: BodyProfile) -> Double? {
        guard let heightCM = body.heightCM, heightCM > 0 else { return nil }
        guard let extent = extendedExtent(frames: frames), extent > 0.02 else { return nil }
        let trackedMetres = (heightCM / 100) * noseToAnkleFraction
        return trackedMetres / extent
    }

    /// How tall the tracked joints stood at the climber's most extended, in
    /// normalised image units.
    ///
    /// The 95th percentile rather than the maximum: one frame of bad tracking
    /// can stretch a joint far outside the body, and the maximum would take that
    /// frame at its word.
    static func extendedExtent(frames: [PoseFrame]) -> Double? {
        let extents = frames.compactMap { rawExtent($0) }.sorted()
        guard !extents.isEmpty else { return nil }
        let index = Int((Double(extents.count - 1) * 0.95).rounded())
        return extents[index]
    }

    /// The vertical spread of one frame's joints, unpadded.
    static func rawExtent(_ frame: PoseFrame) -> Double? {
        let ys = JointID.allCases.compactMap { frame.pt($0) }.map { Double($0.y) }
        guard ys.count >= 5, let lo = ys.min(), let hi = ys.max() else { return nil }
        return hi - lo
    }

    // MARK: What the scale is for

    /// The radius of the climber's reach, in normalised image units.
    ///
    /// Half the span, because the envelope is drawn on the centre of mass and an
    /// arm reaches out from roughly the middle of the body. Without a recorded
    /// span there is no honest answer, so the overlay keeps its proportional
    /// fallback instead of inventing one.
    static func reachRadius(frames: [PoseFrame], body: BodyProfile) -> Double? {
        guard let spanCM = body.spanCM, spanCM > 0,
              let mpu = metresPerUnit(frames: frames, body: body), mpu > 0
        else { return nil }
        return (spanCM / 200) / mpu
    }

    // MARK: Lifting

    /// How much of the climb was spent going up, and how much of that you paid
    /// for twice.
    ///
    /// `net` is the rise from the lowest point of the centre-of-mass path to the
    /// highest: the lifting the route actually asked for. `gross` is the sum of
    /// every upward step, which includes every time you dropped back down and
    /// lifted the same weight again. Their ratio needs no scale at all, which is
    /// why it is reported even with nothing entered on the personal info screen.
    ///
    /// Image coordinates grow downward, so a rise is a fall in y.
    struct Lift {
        /// Normalised image units.
        var net: Double
        var gross: Double
        /// Gross over net. 1.0 is a climb with no lost height in it.
        var ratio: Double { net > 0.0001 ? gross / net : 1 }
    }

    static func lift(path: [CGPoint]) -> Lift? {
        guard path.count > 1 else { return nil }
        let ys = path.map { Double($0.y) }
        let net = (ys.max() ?? 0) - (ys.min() ?? 0)
        var gross = 0.0
        for i in 1..<ys.count {
            let rise = ys[i - 1] - ys[i]
            if rise > 0 { gross += rise }
        }
        return Lift(net: net, gross: gross)
    }

    static let g = 9.80665

    /// The work done lifting the body, in joules.
    ///
    /// Gravity only, and only the going-up part: no tendon, no friction, no heat.
    /// It is a floor on the energy the climb cost, not the cost itself, and the
    /// screen says so rather than letting the number imply more than it holds.
    static func work(joules lift: Lift, metresPerUnit: Double?, body: BodyProfile) -> (net: Double, gross: Double)? {
        guard let metresPerUnit, metresPerUnit > 0,
              let mass = body.massKG, mass > 0 else { return nil }
        let k = mass * g * metresPerUnit
        return (lift.net * k, lift.gross * k)
    }

    /// A speed in normalised units per second, said in metres per second.
    static func metresPerSecond(_ normalised: Double, metresPerUnit: Double?) -> Double? {
        guard let metresPerUnit else { return nil }
        return normalised * metresPerUnit
    }
}
