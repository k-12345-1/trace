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

    enum Side: String { case left, right }

    /// One hand move in the plan.
    struct Step: Equatable {
        let hand: Side
        /// Index into the line's hand holds.
        let to: Int
        /// True when the hand joins the other on the same hold.
        let match: Bool
    }

    /// The sequence the planner chose: which hand goes where, in order, and
    /// the hand holds in the order they are first used, for numbering.
    struct Plan {
        let steps: [Step]
        let order: [Int]
        /// Where each hand is after each step, the start first.
        let states: [(left: Int, right: Int)]
    }

    struct Sequence {
        let stances: [Pose]
        let plan: Plan?
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
    struct Shape: Equatable {
        /// Height over span. One for the average body.
        let heightOverSpan: Double
        /// Every length is a share of the arm span, so the figure scales
        /// with the gaps between holds the way a body scales with a wall.
        var upperArm: Double = 0.19
        var forearm: Double = 0.19
        var shoulderWidth: Double = 0.22
        var hipWidth: Double = 0.16
        var torso: Double
        var thigh: Double
        var shin: Double
        var headRadius: Double
        /// True when the lengths were read off this person's own footage
        /// rather than taken from the average body.
        var measured = false
        var arm: Double { upperArm + forearm }
        var leg: Double { thigh + shin }

        static let average = Shape(heightOverSpan: 1.0)

        init(heightOverSpan: Double) {
            self.heightOverSpan = heightOverSpan
            torso = 0.30 * heightOverSpan
            thigh = 0.245 * heightOverSpan
            shin = 0.225 * heightOverSpan
            headRadius = 0.055 * heightOverSpan
        }

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
        read(line: line, shape: Shape(body))
    }

    static func read(line: LineEngine.Line, shape: Shape) -> Sequence? {
        let hands = line.hands.map { CGPoint(x: $0.midX, y: $0.midY) }
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        guard hands.count >= 2 else { return nil }
        var gaps: [Double] = []
        for (a, b) in zip(hands, hands.dropFirst()) { gaps.append(distance(a, b)) }
        let median = LineEngine.medianOf(gaps)
        guard median > 1e-6 else { return nil }
        let span = median * spansPerGap

        let plan = self.plan(line: line, span: span, shape: shape)
        // Hands at each stance: the planned states, or, when no plan could
        // be found, one hand at a time up the hand holds.
        var pairs: [(CGPoint, CGPoint)] = []
        if let plan {
            pairs = plan.states.map { (hands[$0.left], hands[$0.right]) }
        } else {
            if line.startCount == 1 { pairs.append((hands[0], hands[0])) }
            for i in 1..<hands.count { pairs.append((hands[i - 1], hands[i])) }
        }

        var stances: [Pose] = []
        for (a, b) in pairs {
            let (l, r) = a.x <= b.x ? (a, b) : (b, a)
            // Feet may use any hold a hand is not on, foot chips included.
            let feetFrom = all.filter { $0 != a && $0 != b }
            stances.append(stance(leftHand: l, rightHand: r, feetFrom: feetFrom,
                                  span: span, shape: shape))
        }
        return Sequence(stances: stances, plan: plan, span: span, shape: shape)
    }

    // MARK: Planning the sequence

    /// A hand goes to a hold no lower than this, in spans, below where it is.
    static let handDrop = 0.1
    /// Costs, in units of one span of reach. Alternating hands is the
    /// baseline; using the same hand twice costs as much as a short reach;
    /// crossing hands costs more; a stance whose hips sit off the feet
    /// costs by how far; a smeared foot costs a little; and a match on a
    /// hold the hand has to share is cheap, because a jug is where you rest.
    static let reachCost = 0.6
    static let sameHandCost = 0.35
    static let crossCost = 0.8
    static let smearCost = 0.25
    static let hipsOffCost = 1.2
    static let matchCost = 0.15

    /// The cheapest way from the start holds to the finish, one hand at a
    /// time, judged by the stance each move leaves the body in.
    ///
    /// Dijkstra over where the two hands are and which moved last. A hand
    /// may go to any hand hold within the arm span of the other hand and no
    /// lower than where it is, and the finish is both hands on the finish
    /// holds, or matched on the top hold when none were marked. The feet at
    /// each state are chosen the way the figure chooses them, so the cost
    /// of a move is the cost of the position it ends in: how far the hand
    /// went, whether it crossed, whether the same hand went again, and how
    /// well the body stands there.
    static func plan(line: LineEngine.Line, span: Double, shape: Shape) -> Plan? {
        let hands = line.hands.map { CGPoint(x: $0.midX, y: $0.midY) }
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        let n = hands.count
        guard n >= 2 else { return nil }
        let arm = shape.arm * span

        // Start and finish.
        let start: (Int, Int)
        switch line.startCount {
        case 2: start = hands[0].x <= hands[1].x ? (0, 1) : (1, 0)
        case 1: start = (0, 0)
        default:
            // The lowest hand hold and, if close enough, the next: otherwise
            // both hands on the lowest.
            let lowest = (0..<n).min { hands[$0].y > hands[$1].y }!
            let second = (0..<n).filter { $0 != lowest }.min { distance(hands[$0], hands[lowest]) < distance(hands[$1], hands[lowest]) }
            if let second, distance(hands[second], hands[lowest]) <= span * 0.95, hands[second].y <= hands[lowest].y + handDrop * span {
                start = hands[lowest].x <= hands[second].x ? (lowest, second) : (second, lowest)
            } else { start = (lowest, lowest) }
        }
        let finishSet: Set<Int> = {
            let tagged = Set(line.finishes.compactMap { f in line.hands.firstIndex(of: f) })
            if !tagged.isEmpty { return tagged }
            return [(0..<n).min { hands[$0].y < hands[$1].y }!]
        }()
        func isGoal(_ l: Int, _ r: Int) -> Bool { finishSet.contains(l) && finishSet.contains(r) }

        // The stance at a hand pair, cached.
        var stanceCost: [Int: Double] = [:]
        func costOfStanding(_ l: Int, _ r: Int) -> Double {
            let key = l * n + r
            if let c = stanceCost[key] { return c }
            let a = hands[l], b = hands[r]
            let feetFrom = all.filter { $0 != a && $0 != b }
            let pose = stance(leftHand: a.x <= b.x ? a : b, rightHand: a.x <= b.x ? b : a,
                              feetFrom: feetFrom, span: span, shape: shape)
            var c = 0.0
            if pose.leftFootHold == nil { c += smearCost }
            if pose.rightFootHold == nil { c += smearCost }
            let feetX = (pose.leftFoot.x + pose.rightFoot.x) / 2
            c += hipsOffCost * min(1, abs(pose.hips.x - feetX) / span)
            stanceCost[key] = c
            return c
        }

        // Dijkstra. State: left hold, right hold, which hand moved last.
        struct State: Hashable { let l: Int; let r: Int; let last: Int }  // last: 0 left, 1 right, 2 none
        var best: [State: Double] = [:]
        var from: [State: (State, Step)] = [:]
        let origin = State(l: start.0, r: start.1, last: 2)
        best[origin] = 0
        var open: [(Double, State)] = [(0, origin)]
        var goal: State?
        while !open.isEmpty {
            open.sort { $0.0 > $1.0 }
            let (d, st) = open.removeLast()
            if d > (best[st] ?? .infinity) { continue }
            if isGoal(st.l, st.r) { goal = st; break }
            for mover in 0...1 {
                let staying = mover == 0 ? st.r : st.l
                let current = mover == 0 ? st.l : st.r
                for j in 0..<n where j != current {
                    // Within reach of the hand that stays, and not downward.
                    guard distance(hands[j], hands[staying]) <= span * 0.95 || j == staying else { continue }
                    guard hands[j].y <= hands[current].y + handDrop * span else { continue }
                    let l = mover == 0 ? j : st.l, r = mover == 0 ? st.r : j
                    // Reach costs by its square: a hand that goes one arm's
                    // length is cheap, one that goes two is a throw. Judged
                    // linearly, three long throws beat seven short moves.
                    let reach = distance(hands[j], hands[current]) / max(arm, 1e-6)
                    var c = reachCost * reach * reach
                    if st.last == mover { c += sameHandCost }
                    if hands[l].x > hands[r].x + 0.02 { c += crossCost }
                    if j == staying { c += matchCost }
                    c += costOfStanding(l, r)
                    let next = State(l: l, r: r, last: mover)
                    let nd = d + c
                    if nd < (best[next] ?? .infinity) {
                        best[next] = nd
                        from[next] = (st, Step(hand: mover == 0 ? .left : .right, to: j, match: j == staying))
                        open.append((nd, next))
                    }
                }
            }
        }
        guard let goal else { return nil }
        var steps: [Step] = []
        var states: [(left: Int, right: Int)] = [(goal.l, goal.r)]
        var cursor = goal
        while let (prev, step) = from[cursor] {
            steps.append(step); states.append((prev.l, prev.r)); cursor = prev
        }
        steps.reverse(); states.reverse()
        var order: [Int] = []
        for s in states { for h in [s.left, s.right] where !order.contains(h) { order.append(h) } }
        return Plan(steps: steps, order: order, states: states)
    }

    /// The plan said in words, one line per move, with the holds numbered
    /// in the order the plan first uses them.
    static func describe(_ plan: Plan, line: LineEngine.Line) -> [String] {
        func number(_ i: Int) -> Int { (plan.order.firstIndex(of: i) ?? i) + 1 }
        var out: [String] = []
        switch line.startCount {
        case 2: out.append("Start with a hand on each of 1 and 2.")
        case 1: out.append("Start with both hands on 1.")
        default: out.append(plan.states.first.map { $0.left == $0.right ? "Start with both hands on 1." : "Start with a hand on each of 1 and 2." } ?? "")
        }
        for s in plan.steps {
            let hand = s.hand == .left ? "Left" : "Right"
            out.append(s.match ? "\(hand) hand matches on \(number(s.to))." : "\(hand) hand to \(number(s.to)).")
        }
        return out
    }

    /// The body hung from two hands, standing on what it can.
    /// The older entry, kept for the tests that build a stance from a list.
    static func stance(leftHand: CGPoint, rightHand: CGPoint, holds: [CGPoint],
                       handIndex: Int, span: Double, shape: Shape = .average) -> Pose {
        let feetFrom = holds.enumerated().filter { k, _ in k < handIndex - 1 || k > handIndex }.map(\.element)
        return stance(leftHand: leftHand, rightHand: rightHand, feetFrom: feetFrom, span: span, shape: shape)
    }

    static func stance(leftHand: CGPoint, rightHand: CGPoint, feetFrom: [CGPoint],
                       span: Double, shape: Shape = .average) -> Pose {
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
        let candidates = feetFrom.enumerated().filter { _, h in
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
