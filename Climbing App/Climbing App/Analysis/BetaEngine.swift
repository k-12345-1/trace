import Foundation
import CoreGraphics

/// A figure climbing the line, one stance per hold.
///
/// ## What this is
///
/// The line says which order the holds go in. This puts a body on them: at
/// each stance both hands are on consecutive holds, the shoulders hang below
/// them on arms as straight as the holds allow, the hips hang below the
/// shoulders, and the feet find the highest holds below the hips that a leg
/// can reach, or smear the wall if there are none. Scrub between stances and
/// the figure moves through the route.
///
/// ## What it is not
///
/// It is not the beta. A photograph has no scale, no hold types, no wall
/// angle, and no idea which way a hold faces, so this is one plausible shape
/// through the line, drawn to show the order and the reaches, not the
/// sequence a setter intended. Every screen that shows it says so.
///
/// ## Scale
///
/// There is no scale in the photo, so the figure is sized from the route: the
/// arm span is taken as a fixed multiple of the route's median gap between
/// holds. Gym boulders put consecutive hand holds roughly half to two thirds
/// of a span apart, which is where `spansPerGap` comes from. A climber's real
/// height changes nothing here, because it cannot: there is nothing in the
/// picture to measure it against.
enum BetaEngine {

    /// One shape on the wall, every point normalized to the photo, origin
    /// top left.
    struct Pose {
        var leftHand: CGPoint, rightHand: CGPoint
        var leftElbow: CGPoint, rightElbow: CGPoint
        var leftShoulder: CGPoint, rightShoulder: CGPoint
        var head: CGPoint
        var hips: CGPoint
        var leftKnee: CGPoint, rightKnee: CGPoint
        var leftFoot: CGPoint, rightFoot: CGPoint
        /// Which holds each foot is on, by index into the line, or nil for a
        /// smear.
        var leftFootHold: Int?, rightFootHold: Int?

        /// The segments to draw, in drawing order.
        var bones: [(CGPoint, CGPoint)] {
            [(leftHand, leftElbow), (leftElbow, leftShoulder),
             (rightHand, rightElbow), (rightElbow, rightShoulder),
             (leftShoulder, rightShoulder),
             (leftShoulder, hips), (rightShoulder, hips),
             (hips, leftKnee), (leftKnee, leftFoot),
             (hips, rightKnee), (rightKnee, rightFoot)]
        }
        var joints: [CGPoint] {
            [leftHand, rightHand, leftElbow, rightElbow, leftShoulder, rightShoulder,
             hips, leftKnee, rightKnee, leftFoot, rightFoot]
        }
    }

    struct Sequence {
        let stances: [Pose]
        /// Arm span in photo units, the scale everything was drawn at.
        let span: Double
        /// The proportions the figure was drawn with.
        let shape: Shape

        /// The figure at a point through the route, 0 at the first stance and
        /// 1 at the last, eased between neighbours.
        func pose(at t: Double) -> Pose? {
            guard let first = stances.first else { return nil }
            guard stances.count > 1 else { return first }
            let scaled = min(max(t, 0), 1) * Double(stances.count - 1)
            let i = min(Int(scaled), stances.count - 2)
            let u = scaled - Double(i)
            let e = 0.5 - 0.5 * cos(u * .pi)
            return blend(stances[i], stances[i + 1], e)
        }
    }

    // MARK: Proportions, in arm spans

    /// The climber's shape, from their profile where they gave one.
    ///
    /// Everything is in arm spans because the span is what reaches between
    /// holds. Height comes in as the ratio of height to span: a plus ape
    /// index makes the legs and torso shorter against the arms, a minus one
    /// longer, which is exactly the difference that decides whether a foot
    /// reaches a hold while the hands stay where they are.
    struct Shape {
        /// Height over span. One for the average body.
        let heightOverSpan: Double
        var upperArm: Double { 0.19 }
        var forearm: Double { 0.19 }
        var shoulderWidth: Double { 0.22 }
        var torso: Double { 0.30 * heightOverSpan }
        var thigh: Double { 0.245 * heightOverSpan }
        var shin: Double { 0.225 * heightOverSpan }
        var headRadius: Double { 0.055 * heightOverSpan }
        var arm: Double { upperArm + forearm }
        var leg: Double { thigh + shin }

        static let average = Shape(heightOverSpan: 1.0)

        init(heightOverSpan: Double) { self.heightOverSpan = heightOverSpan }

        init(_ body: BodyProfile) {
            if let h = body.heightCM, let s = body.spanCM, h > 0, s > 0 {
                self.init(heightOverSpan: min(max(h / s, 0.85), 1.15))
            } else {
                self.init(heightOverSpan: 1.0)
            }
        }
    }

    /// Consecutive hand holds on a gym boulder, as a fraction of a span.
    static let spansPerGap = 2.6
    /// A foot will not go higher than this above the hips, in spans. Hip
    /// height is a high step, and the coaches say not to.
    static let highestFoot = -0.05
    /// A leg can take a hold a little past its straight length, because the
    /// hips come across to meet it: a rock-over.
    static let legStretch = 1.25
    /// How far the hips move toward the feet when they are on holds, as a
    /// share of the gap. Weight over the feet, which is the thing every
    /// finding in this app is about.
    static let hipsTowardFeet = 0.45
    /// Where a smeared foot goes when there is no hold for it.
    static let smearDrop = 0.44
    static let smearOut = 0.10

    // MARK: Reading

    static func read(line: LineEngine.Line, body: BodyProfile = .empty) -> Sequence? {
        let shape = Shape(body)
        let holds = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        guard holds.count >= 2 else { return nil }
        var gaps: [Double] = []
        for (a, b) in zip(holds, holds.dropFirst()) { gaps.append(distance(a, b)) }
        let median = LineEngine.medianOf(gaps)
        guard median > 1e-6 else { return nil }
        let span = median * spansPerGap

        var stances: [Pose] = []
        for i in 0..<(holds.count - 1) {
            let a = holds[i], b = holds[i + 1]
            // Left hand on the left of the pair, whichever came first.
            let (l, r) = a.x <= b.x ? (a, b) : (b, a)
            stances.append(stance(leftHand: l, rightHand: r, holds: holds,
                                  handIndex: i + 1, span: span, shape: shape))
        }
        return Sequence(stances: stances, span: span, shape: shape)
    }

    /// The body hung from two hands, standing on what it can.
    static func stance(leftHand: CGPoint, rightHand: CGPoint, holds: [CGPoint],
                       handIndex: Int, span: Double, shape: Shape = .average) -> Pose {
        let arm = shape.arm * span
        let mid = CGPoint(x: (leftHand.x + rightHand.x) / 2, y: (leftHand.y + rightHand.y) / 2)
        let handGap = distance(leftHand, rightHand)

        // Shoulders below the hands, as far as the arms allow. Each shoulder
        // sits under its hand, so with the hands wide the arms open into a V
        // and with them close the shoulders drop straight down.
        let half = min(handGap / 2, shape.shoulderWidth * span / 2)
        // Hands further apart than two arms is a stance this body cannot
        // make. It used to take the square root of a negative number here
        // and every joint but the hands became NaN, which on the screen was
        // the climber vanishing at stance nine of twelve. Now the arms
        // stretch to meet it and the shoulders sit just under the hands:
        // wrong by a little, visibly, rather than gone.
        let slack = min(max(0, handGap / 2 - half), arm * 0.95)
        let reach = max(0, arm * arm - slack * slack).squareRoot()
        let drop = max(reach * 0.92, arm * 0.25)   // arms nearly straight, not locked
        var neck = CGPoint(x: mid.x, y: mid.y + drop)
        var hips = CGPoint(x: mid.x, y: neck.y + shape.torso * span)

        // Feet first, because the feet decide where the hips go. The highest
        // holds below the hips a leg can reach, one each side where possible,
        // never a hold a hand is on. A leg may take a hold a little past its
        // straight length, because the hips will come across to it.
        let leg = shape.leg * span
        let candidates = holds.enumerated().filter { k, _ in
            k < handIndex - 1 || k > handIndex
        }.filter { _, h in
            h.y - hips.y >= highestFoot * span && distance(h, hips) <= leg * legStretch
        }
        var leftPick = candidates.filter { $0.element.x <= hips.x }.min { $0.element.y < $1.element.y }
        var rightPick = candidates.filter { $0.element.x > hips.x }.min { $0.element.y < $1.element.y }
        // One side empty: the other side's next hold beats smearing, both feet
        // to one side with the hips brought over.
        if leftPick == nil, let r = rightPick {
            leftPick = candidates.filter { $0.offset != r.offset && $0.element.x > hips.x }
                .min { $0.element.y < $1.element.y }
        } else if rightPick == nil, let l = leftPick {
            rightPick = candidates.filter { $0.offset != l.offset && $0.element.x <= hips.x }
                .min { $0.element.y < $1.element.y }
        }
        if let l = leftPick, let r = rightPick, l.element.x > r.element.x { swap(&leftPick, &rightPick) }

        // Weight over the feet. With feet on holds the hips come toward them,
        // as far as the arms allow the shoulders to follow.
        let onHolds = [leftPick, rightPick].compactMap { $0?.element }
        if !onHolds.isEmpty {
            let feetX = onHolds.map(\.x).reduce(0, +) / Double(onHolds.count)
            var dx = (feetX - hips.x) * hipsTowardFeet
            let used = max(distance(leftHand, CGPoint(x: neck.x - half, y: neck.y)),
                           distance(rightHand, CGPoint(x: neck.x + half, y: neck.y)))
            let limit = max(0, arm - used)
            dx = min(max(dx, -limit), limit)
            neck.x += dx; hips.x += dx
        }
        let ls = CGPoint(x: neck.x - half, y: neck.y)
        let rs = CGPoint(x: neck.x + half, y: neck.y)
        let head = CGPoint(x: neck.x, y: neck.y - shape.headRadius * span * 1.6)

        // Elbows bow outward a little, so a straight arm still reads as one.
        func elbow(_ hand: CGPoint, _ shoulder: CGPoint, out: Double) -> CGPoint {
            let m = CGPoint(x: (hand.x + shoulder.x) / 2, y: (hand.y + shoulder.y) / 2)
            return CGPoint(x: m.x + out * span * 0.05, y: m.y)
        }

        func foot(_ pick: (offset: Int, element: CGPoint)?, side: Double) -> (CGPoint, Int?) {
            if let pick { return (pick.element, pick.offset) }
            return (CGPoint(x: hips.x + side * smearOut * span, y: hips.y + smearDrop * span), nil)
        }
        let (lf, lfi) = foot(leftPick, side: -1)
        let (rf, rfi) = foot(rightPick, side: 1)

        func knee(_ f: CGPoint, side: Double) -> CGPoint {
            let m = CGPoint(x: (hips.x + f.x) / 2, y: (hips.y + f.y) / 2)
            // The knee bends out to the side, more the higher the foot is.
            let bend = max(0, 1 - (f.y - hips.y) / leg) * 0.12 * span
            return CGPoint(x: m.x + side * (0.03 * span + bend), y: m.y)
        }

        return Pose(leftHand: leftHand, rightHand: rightHand,
                    leftElbow: elbow(leftHand, ls, out: -1), rightElbow: elbow(rightHand, rs, out: 1),
                    leftShoulder: ls, rightShoulder: rs,
                    head: head, hips: hips,
                    leftKnee: knee(lf, side: -1), rightKnee: knee(rf, side: 1),
                    leftFoot: lf, rightFoot: rf,
                    leftFootHold: lfi, rightFootHold: rfi)
    }

    // MARK: Helpers

    static func blend(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func mix(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
        }
        return Pose(leftHand: mix(a.leftHand, b.leftHand), rightHand: mix(a.rightHand, b.rightHand),
                    leftElbow: mix(a.leftElbow, b.leftElbow), rightElbow: mix(a.rightElbow, b.rightElbow),
                    leftShoulder: mix(a.leftShoulder, b.leftShoulder), rightShoulder: mix(a.rightShoulder, b.rightShoulder),
                    head: mix(a.head, b.head), hips: mix(a.hips, b.hips),
                    leftKnee: mix(a.leftKnee, b.leftKnee), rightKnee: mix(a.rightKnee, b.rightKnee),
                    leftFoot: mix(a.leftFoot, b.leftFoot), rightFoot: mix(a.rightFoot, b.rightFoot),
                    leftFootHold: t < 0.5 ? a.leftFootHold : b.leftFootHold,
                    rightFootHold: t < 0.5 ? a.rightFootHold : b.rightFootHold)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    static let caveat = "One shape through the line, drawn to show the order and the reaches. Trace cannot see hold types, the wall's angle, or which way a hold faces, so this is not the sequence. The figure has your proportions if you have given Trace your height and span, and is sized to the route, because a photograph cannot measure a person."
}
