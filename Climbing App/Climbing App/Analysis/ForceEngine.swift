import Foundation
import CoreGraphics

/// Friction, and the force pairs that make it.
///
/// A hold does not hold you. Friction does, and friction is `f = μN`: the
/// coefficient of the rubber or skin against the hold, times the force pressing
/// into it. μ belongs to the materials and you cannot argue with it. N is the
/// entire negotiation, and N is what a climber actually controls.
///
/// There are only two ways to make N. Gravity can do it, when you hang below a
/// hold and your weight presses into it. Or you can make it yourself, by
/// pressing two contacts toward each other so their forces cancel: a pinch, a
/// gaston against a sidepull, a hand pulling in while a foot pushes out. Those
/// are **force pairs**, and they are why a compression problem is climbable at
/// all on holds that would hold nothing if you simply hung off them.
///
/// The angle matters and it is where friction is quietly thrown away. Only the
/// component of your pull along the hold's normal becomes N: pull at α off that
/// line and you get `N = F cos α`, so friction becomes `f = μF cos α`. Thirty
/// degrees off costs thirteen percent of your friction. Sixty degrees costs half
/// of it. Nothing about the hold changed.
///
/// ## What Trace can and cannot see
///
/// The phone is square to the wall, so the image plane is the wall plane. Across
/// and up the wall are measured directly. **Distance from the wall is not
/// measured at all.** That is one axis of the geometry gone, and it rules out
/// the calculation everyone wants first: Trace cannot tell you the angle between
/// your pull and a hold's normal, because it can see neither how far your hips
/// are off the wall nor which way the hold faces.
///
/// What is left is still the important half. Whether your contacts bracket your
/// center of mass, whether two of them are loaded toward each other, and how far
/// off vertical each limb is loaded are all in the wall plane, and they are what
/// decides whether the force pair exists at all. The magnitudes are out of
/// reach; the geometry is not, and the geometry is the part you can change.
enum ForceEngine {

    // MARK: Contacts

    /// A loaded contact, in the wall plane.
    struct Contact {
        let point: CGPoint
        let isHand: Bool
    }

    static func contacts(_ f: PoseFrame) -> [Contact] {
        var out: [Contact] = []
        if let p = f.pt(.leftWrist)  { out.append(Contact(point: p, isHand: true)) }
        if let p = f.pt(.rightWrist) { out.append(Contact(point: p, isHand: true)) }
        if let p = f.pt(.leftAnkle)  { out.append(Contact(point: p, isHand: false)) }
        if let p = f.pt(.rightAnkle) { out.append(Contact(point: p, isHand: false)) }
        return out
    }

    // MARK: Bracketing

    /// Whether the center of mass sits horizontally between the outermost
    /// contacts.
    ///
    /// This is the whole of opposition reduced to one question. When the center
    /// of mass is inside the span, the horizontal pulls on the contacts point
    /// toward each other and cancel: a force pair, and you are still. When it is
    /// outside, nothing cancels the sideways component and the body rotates
    /// about the outermost contact. That is a barndoor, and it is not a lapse of
    /// strength, it is a missing second force.
    static func isBracketed(_ f: PoseFrame) -> Bool? {
        guard let com = f.com else { return nil }
        let xs = contacts(f).map(\.point.x)
        guard let lo = xs.min(), let hi = xs.max(), xs.count >= 2 else { return nil }
        return com.x >= lo && com.x <= hi
    }

    /// How far outside the span the center of mass is, in torso lengths. Zero
    /// when it is inside. This is the lever arm of the swing.
    static func overhang(_ f: PoseFrame) -> Double? {
        guard let com = f.com, let torso = MetricsEngine.torsoLength(f), torso > 0.01 else { return nil }
        let xs = contacts(f).map(\.point.x)
        guard let lo = xs.min(), let hi = xs.max(), xs.count >= 2 else { return nil }
        if com.x < lo { return (lo - com.x) / torso }
        if com.x > hi { return (com.x - hi) / torso }
        return 0
    }

    // MARK: Compression

    /// Hands must be this far apart, in torso lengths, before squeezing between
    /// them is what is holding you on. Closer than this and they are two hands
    /// on the same hold rather than a pair opposing each other.
    static let compressionSpan = 1.0

    /// Both hands loaded toward each other, with the body hanging between them.
    ///
    /// Geometrically: the hands are wide, and the center of mass is between
    /// them. Each hand's load then has a horizontal component pointing at the
    /// other one, which is the force pair making its own normal force. This is
    /// the one situation where friction is manufactured rather than borrowed
    /// from gravity.
    static func isCompressing(_ f: PoseFrame) -> Bool? {
        guard let com = f.com,
              let left = f.pt(.leftWrist), let right = f.pt(.rightWrist),
              let torso = MetricsEngine.torsoLength(f), torso > 0.01 else { return nil }
        let span = abs(right.x - left.x) / torso
        guard span >= compressionSpan else { return false }
        let lo = min(left.x, right.x), hi = max(left.x, right.x)
        return com.x > lo && com.x < hi
    }

    // MARK: Load angle

    /// How far off vertical a limb is loaded, in degrees.
    ///
    /// The body hangs from the contact toward the center of mass, so that line
    /// is the direction of the load. Zero is straight down, which is what a
    /// downward facing hold wants. This is not the angle in `N = F cos α`: that
    /// one is measured against the hold's normal, which Trace cannot see. It is
    /// the part of the geometry that is visible, and a limb loaded far off
    /// vertical is either on a sidepull, or being used as half of a force pair,
    /// or about to swing.
    static func loadAngle(from contact: CGPoint, to com: CGPoint) -> Double {
        let dx = com.x - contact.x
        let dy = com.y - contact.y          // origin top left, so down is positive
        return abs(atan2(dx, max(dy, 0.0001))) * 180 / .pi
    }

    static func handAngles(_ f: PoseFrame) -> [Double] {
        guard let com = f.com else { return [] }
        return [f.pt(.leftWrist), f.pt(.rightWrist)]
            .compactMap { $0 }
            .map { loadAngle(from: $0, to: com) }
    }

    // MARK: Over a whole climb

    /// The share of tracked time the center of mass was inside the contacts.
    static func bracketedFraction(frames: [PoseFrame]) -> Double {
        let readings = frames.compactMap { isBracketed($0) }
        guard !readings.isEmpty else { return 0 }
        return Double(readings.filter { $0 }.count) / Double(readings.count)
    }

    /// The share of tracked time spent squeezing between two wide hands.
    static func compressionFraction(frames: [PoseFrame]) -> Double {
        let readings = frames.compactMap { isCompressing($0) }
        guard !readings.isEmpty else { return 0 }
        return Double(readings.filter { $0 }.count) / Double(readings.count)
    }

    /// A swing has to be this far out, and last this long, before it is a
    /// position rather than a moment in transit. Every dynamic move passes
    /// through an unbracketed instant and none of those is a fault.
    static let swingOverhang = 0.35
    static let swingSeconds = 0.5

    struct Swing {
        let start: Double
        let end: Double
        /// The worst lever arm reached, in torso lengths.
        let peak: Double
        var duration: Double { max(0, end - start) }
    }

    /// Spans where the center of mass hung outside the contacts long enough to
    /// be holding a position there.
    static func swings(frames: [PoseFrame]) -> [Swing] {
        var out: [Swing] = []
        var start: Double?
        var peak = 0.0
        var last: Double?

        for f in frames {
            guard let over = overhang(f) else { continue }
            if over > swingOverhang {
                if start == nil { start = f.time; peak = over }
                peak = max(peak, over)
                last = f.time
            } else if let s = start, let e = last {
                if e - s >= swingSeconds { out.append(Swing(start: s, end: e, peak: peak)) }
                start = nil; peak = 0; last = nil
            }
        }
        if let s = start, let e = last, e - s >= swingSeconds {
            out.append(Swing(start: s, end: e, peak: peak))
        }
        return out
    }

    /// Total seconds spent swinging.
    static func swingTotal(frames: [PoseFrame]) -> Double {
        swings(frames: frames).reduce(0) { $0 + $1.duration }
    }

    // MARK: The number people ask for

    /// The share of a pull that becomes normal force, `cos α`.
    ///
    /// Trace never measures α on a real climb, for the reason given at the top
    /// of this file. This exists so the explanation on the results screen quotes
    /// arithmetic rather than a remembered figure, and so the claim that thirty
    /// degrees costs thirteen percent is checked by a test rather than asserted.
    static func normalShare(offBy degrees: Double) -> Double {
        cos(degrees * .pi / 180)
    }

    /// The same thing said as a loss: 30 degrees returns 13.
    static func frictionLost(offBy degrees: Double) -> Int {
        Int(((1 - normalShare(offBy: degrees)) * 100).rounded())
    }
}
