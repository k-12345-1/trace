import Foundation
import CoreGraphics

/// Turning pixels into meters.
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

    /// Meters per unit of normalized image height, or nil when there is nothing
    /// to work from.
    static func metersPerUnit(frames: [PoseFrame], body: BodyProfile) -> Double? {
        guard let heightCM = body.heightCM, heightCM > 0 else { return nil }
        guard let extent = extendedExtent(frames: frames), extent > 0.02 else { return nil }
        let trackedMeters = (heightCM / 100) * noseToAnkleFraction
        return trackedMeters / extent
    }

    /// How tall the tracked joints stood at the climber's most extended, in
    /// normalized image units.
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

    /// The radius of the climber's reach, in normalized image units.
    ///
    /// Half the span, because the envelope is drawn on the center of mass and an
    /// arm reaches out from roughly the middle of the body. Without a recorded
    /// span there is no honest answer, so the overlay keeps its proportional
    /// fallback instead of inventing one.
    static func reachRadius(frames: [PoseFrame], body: BodyProfile) -> Double? {
        guard let spanCM = body.spanCM, spanCM > 0,
              let mpu = metersPerUnit(frames: frames, body: body), mpu > 0
        else { return nil }
        return (spanCM / 200) / mpu
    }

    // MARK: Lifting

    /// How much of the climb was spent going up, and how much of that you paid
    /// for twice.
    ///
    /// `net` is the rise from the lowest point of the center-of-mass path to the
    /// highest: the lifting the route actually asked for. `gross` is the rise
    /// the climber actually paid for, which is more than the net whenever they
    /// dropped back down and lifted the same weight again. Their ratio needs no
    /// scale at all, which is why it is reported even with nothing entered on
    /// the personal info screen.
    ///
    /// ## Why a descent has to be big enough to count
    ///
    /// `gross` used to be the sum of every frame-to-frame upward step, which
    /// turns out to measure the tracker rather than the climber. A real clip at
    /// 60fps carries a few thousandths of a torso length of jitter on every
    /// frame, in both directions, and summing only the upward half of it adds
    /// that noise to the total a thousand times over. On the first real climb
    /// Trace was ever shown, a clean ascent with no drop in it anywhere, the
    /// summed steps came to 9.73 torso lengths against a true rise of 5.69, and
    /// the app told a climber who never once lost height that 68 percent of it
    /// had been gained twice. It also scaled with frame rate: twice the frames,
    /// twice the noise steps, same climb.
    ///
    /// So a direction change only counts once the body has gone back the other
    /// way by `reversalDeadband` of a torso length. Clearing the noise sets the
    /// floor: on that clip the median per-frame step was 0.0045 torso and the
    /// 99th percentile 0.045, so anything from about 0.05 up is above every
    /// single frame of jitter. But clearing the noise is not enough, because
    /// what is left at 0.10 is still not re-lifting. It is the ordinary
    /// oscillation of climbing: the hips drop when a foot comes up and the
    /// rock-over takes it back. That climber dipped fifteen times and never once
    /// by more than 0.28 of a torso length, and being told half their height was
    /// gained twice describes the mechanics of climbing rather than anything
    /// they did wrong.
    ///
    /// The band is `WasteEngine.returnRadius`, which is the distance at which
    /// Trace already says a body is back where it started. Two measures of
    /// movement that got you nowhere should not disagree about what counts as
    /// movement, and this one had the lower bar by a factor of three.
    ///
    /// Image coordinates grow downward, so a rise is a fall in y.
    struct Lift {
        /// Normalized image units.
        var net: Double
        var gross: Double
        /// Gross over net. 1.0 is a climb with no lost height in it.
        var ratio: Double { net > 0.0001 ? gross / net : 1 }
    }

    /// How far back down the body has to go before it counts as having gone
    /// down, in torso lengths. Deliberately the same number as
    /// `WasteEngine.returnRadius`.
    static let reversalDeadband = WasteEngine.returnRadius

    /// `torso` is the climber's torso length in the same units as the path, so
    /// the band means the same thing however far away the phone was. It is
    /// required rather than optional: a default would be a number in image
    /// units, and an image unit is not a length.
    static func lift(path: [CGPoint], torso: Double) -> Lift? {
        guard path.count > 1, torso > 0 else { return nil }
        let ys = path.map { Double($0.y) }
        let net = (ys.max() ?? 0) - (ys.min() ?? 0)
        let band = torso * reversalDeadband

        // A zigzag filter. `pivot` is the last confirmed turn, `candidate` the
        // furthest the body has got since, and a leg is only banked once the
        // body has come back off that extreme by the band.
        var gross = 0.0
        var pivot = ys[0], candidate = ys[0]
        var rising = true
        for y in ys.dropFirst() {
            if rising {
                if y < candidate { candidate = y }          // higher still
                if y - candidate > band {                   // turned back down
                    gross += max(0, pivot - candidate)
                    pivot = candidate; candidate = y; rising = false
                }
            } else {
                if y > candidate { candidate = y }          // lower still
                if candidate - y > band {                   // turned back up
                    pivot = candidate; candidate = y; rising = true
                }
            }
        }
        if rising { gross += max(0, pivot - candidate) }

        return Lift(net: net, gross: gross)
    }

    static let g = 9.80665

    /// The work done lifting the body, in joules.
    ///
    /// Gravity only, and only the going-up part: no tendon, no friction, no heat.
    /// It is a floor on the energy the climb cost, not the cost itself, and the
    /// screen says so rather than letting the number imply more than it holds.
    static func work(joules lift: Lift, metersPerUnit: Double?, body: BodyProfile) -> (net: Double, gross: Double)? {
        guard let metersPerUnit, metersPerUnit > 0,
              let mass = body.massKG, mass > 0 else { return nil }
        let k = mass * g * metersPerUnit
        return (lift.net * k, lift.gross * k)
    }

    /// A speed in normalized units per second, said in meters per second.
    static func metersPerSecond(_ normalized: Double, metersPerUnit: Double?) -> Double? {
        guard let metersPerUnit else { return nil }
        return normalized * metersPerUnit
    }
}
