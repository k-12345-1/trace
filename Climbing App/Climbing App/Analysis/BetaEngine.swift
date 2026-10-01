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
    enum Limb: String { case leftHand, rightHand, leftFoot, rightFoot
        var isHand: Bool { self == .leftHand || self == .rightHand }
        var name: String {
            switch self {
            case .leftHand: return "Left hand"
            case .rightHand: return "Right hand"
            case .leftFoot: return "Left foot"
            case .rightFoot: return "Right foot"
            }
        }
    }

    /// One move in the plan: a limb to a hold.
    struct Step: Equatable {
        let limb: Limb
        /// Index into the line's holds, every hold. Minus one is a foot
        /// taken off its hold to smear.
        let to: Int
        /// True when a hand joins the other on the same hold.
        let match: Bool
        var hand: Side? { limb == .leftHand ? .left : limb == .rightHand ? .right : nil }
    }

    /// Where every limb is: indices into the line's holds, minus one for a
    /// foot that is smearing.
    struct Position: Hashable {
        var leftHand: Int, rightHand: Int, leftFoot: Int, rightFoot: Int
    }

    /// The sequence the planner chose, and the holds in the order any limb
    /// first uses them, for numbering.
    struct Plan {
        let steps: [Step]
        let order: [Int]
        /// Every position, the start first.
        let states: [Position]
        /// The hand holds in the order the hands first use them, for the
        /// line drawn through them.
        var handOrder: [Int] {
            var out: [Int] = []
            for p in states { for h in [p.leftHand, p.rightHand] where !out.contains(h) { out.append(h) } }
            return out
        }
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
        var stances: [Pose] = []
        if let plan {
            for p in plan.states {
                let a = all[p.leftHand], b = all[p.rightHand]
                let feetFrom = all.filter { $0 != a && $0 != b }
                let lf = p.leftFoot >= 0 ? all[p.leftFoot] : nil
                let rf = p.rightFoot >= 0 ? all[p.rightFoot] : nil
                stances.append(stance(leftHand: a.x <= b.x ? a : b, rightHand: a.x <= b.x ? b : a,
                                      feetFrom: feetFrom, span: span, shape: shape, feet: (lf, rf)))
            }
        } else {
            // No plan: one hand at a time up the hand holds, feet by geometry.
            var pairs: [(CGPoint, CGPoint)] = []
            if line.startCount == 1 { pairs.append((hands[0], hands[0])) }
            for i in 1..<hands.count { pairs.append((hands[i - 1], hands[i])) }
            for (a, b) in pairs {
                let (l, r) = a.x <= b.x ? (a, b) : (b, a)
                let feetFrom = all.filter { $0 != a && $0 != b }
                stances.append(stance(leftHand: l, rightHand: r, feetFrom: feetFrom, span: span, shape: shape))
            }
        }
        return Sequence(stances: stances, plan: plan, span: span, shape: shape)
    }

    // MARK: Planning the sequence

    /// A hand goes to a hold no lower than this, in spans, below where it is.
    static let handDrop = 0.1
    /// Costs, in units of one span of reach. Reach costs by its square: one
    /// arm's length is cheap, two is a throw. Alternating is the baseline;
    /// the same hand twice costs as much as a short reach; crossing hands
    /// costs more; a stance whose hips sit off the feet costs by how far; a
    /// smeared foot costs a little; a match is cheap, because a jug is where
    /// you rest. A foot move has a price of its own, so feet are moved when
    /// they need to be and not every other step.
    static let reachCost = 0.6
    static let sameHandCost = 0.35
    static let crossCost = 0.8
    static let smearCost = 0.25
    static let hipsOffCost = 1.2
    static let matchCost = 0.15
    static let footMoveCost = 0.3
    static let footReachCost = 0.3
    /// The most positions the search will look at before giving up and
    /// leaving the feet to geometry.
    static let searchLimit = 60_000

    /// The cheapest way from the start to the finish, one limb at a time.
    ///
    /// Dijkstra over where all four limbs are and which moved last. A hand
    /// may go to any hand hold within the arm span of the other hand and no
    /// lower than where it is, provided the feet can stay planted under the
    /// hips it leaves: a hold too high for the feet costs a foot move
    /// first, which is how the feet become deliberate. A foot may go
    /// to any hold below the hips within a leg's stretch that no other limb
    /// is on, or come off to smear. The finish is both hands on the finish
    /// holds, or matched on the top hold when none were marked.
    static func plan(line: LineEngine.Line, span: Double, shape: Shape) -> Plan? {
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        let handIndex = line.hands.compactMap { line.holds.firstIndex(of: $0) }
        let isHandHold = Set(handIndex)
        let n = all.count
        guard handIndex.count >= 2 else { return nil }
        let arm = shape.arm * span, leg = shape.leg * span

        // Start: the start holds, or the lowest hand hold and its neighbour.
        var startL: Int, startR: Int
        switch line.startCount {
        case 2: (startL, startR) = (handIndex[0], handIndex[1])
        case 1: (startL, startR) = (handIndex[0], handIndex[0])
        default:
            let lowest = handIndex.min { all[$0].y > all[$1].y }!
            let second = handIndex.filter { $0 != lowest }.min { distance(all[$0], all[lowest]) < distance(all[$1], all[lowest]) }
            if let second, distance(all[second], all[lowest]) <= span * 0.95, all[second].y <= all[lowest].y + handDrop * span {
                (startL, startR) = (lowest, second)
            } else { (startL, startR) = (lowest, lowest) }
        }
        if all[startL].x > all[startR].x { swap(&startL, &startR) }
        let finishSet: Set<Int> = {
            let tagged = Set(line.finishes.compactMap { line.holds.firstIndex(of: $0) })
            if !tagged.isEmpty { return tagged }
            return [handIndex.min { all[$0].y < all[$1].y }!]
        }()

        // The pose at a position, cached, and what standing there costs.
        var poses: [Position: Pose] = [:]
        func pose(_ p: Position) -> Pose {
            if let q = poses[p] { return q }
            let a = all[p.leftHand], b = all[p.rightHand]
            let feetFrom = all.filter { $0 != a && $0 != b }
            let q = stance(leftHand: a.x <= b.x ? a : b, rightHand: a.x <= b.x ? b : a, feetFrom: feetFrom,
                           span: span, shape: shape,
                           feet: (p.leftFoot >= 0 ? all[p.leftFoot] : nil, p.rightFoot >= 0 ? all[p.rightFoot] : nil))
            poses[p] = q
            return q
        }
        func costOfStanding(_ p: Position) -> Double {
            let q = pose(p)
            var c = 0.0
            if p.leftFoot < 0 { c += smearCost }
            if p.rightFoot < 0 { c += smearCost }
            let feetX = (q.leftFoot.x + q.rightFoot.x) / 2
            c += hipsOffCost * min(1, abs(q.hips.x - feetX) / span)
            return c
        }

        // The feet at the start: where geometry would put them.
        let first = Position(leftHand: startL, rightHand: startR, leftFoot: -1, rightFoot: -1)
        let firstPose = stance(leftHand: all[startL], rightHand: all[startR],
                               feetFrom: all.filter { $0 != all[startL] && $0 != all[startR] }, span: span, shape: shape)
        func index(of point: CGPoint) -> Int { all.firstIndex { distance($0, point) < 1e-6 } ?? -1 }
        var origin = first
        if firstPose.leftFootHold != nil { origin.leftFoot = index(of: firstPose.leftFoot) }
        if firstPose.rightFootHold != nil { origin.rightFoot = index(of: firstPose.rightFoot) }

        struct State: Hashable { let p: Position; let last: Int }   // last: 0 lh, 1 rh, 2 lf, 3 rf, 4 none
        var best: [State: Double] = [:]
        var from: [State: (State, Step)] = [:]
        let start = State(p: origin, last: 4)
        best[start] = 0
        var open: [(Double, State)] = [(0, start)]
        var goal: State?
        var looked = 0
        while !open.isEmpty, looked < searchLimit {
            open.sort { $0.0 > $1.0 }
            let (d, st) = open.removeLast()
            if d > (best[st] ?? .infinity) { continue }
            looked += 1
            if finishSet.contains(st.p.leftHand), finishSet.contains(st.p.rightHand) { goal = st; break }
            let here = pose(st.p)
            let occupied: Set<Int> = [st.p.leftHand, st.p.rightHand, st.p.leftFoot, st.p.rightFoot]

            // Hands.
            for mover in 0...1 {
                let current = mover == 0 ? st.p.leftHand : st.p.rightHand
                let staying = mover == 0 ? st.p.rightHand : st.p.leftHand
                for j in handIndex where j != current {
                    guard j == staying || distance(all[j], all[staying]) <= span * 0.95 else { continue }
                    guard all[j].y <= all[current].y + handDrop * span else { continue }
                    guard j == staying || !occupied.contains(j) || j == st.p.leftFoot || j == st.p.rightFoot else { continue }
                    var next = st.p
                    if mover == 0 { next.leftHand = j } else { next.rightHand = j }
                    // A hand taking a foot's hold moves that foot off it.
                    if next.leftFoot == j { next.leftFoot = -1 }
                    if next.rightFoot == j { next.rightFoot = -1 }
                    // The hips rise with the hands. A planted foot has to
                    // still be below them and within a leg's stretch, or
                    // the foot has to move first: that is what makes the
                    // feet deliberate.
                    let after = pose(next)
                    let nextMid = (all[next.leftHand].y + all[next.rightHand].y) / 2
                    let nextHighest = nextMid + arm * 0.25 + shape.torso * span
                    var feetHold = true
                    for f in [next.leftFoot, next.rightFoot] where f >= 0 {
                        if !footReachable(all[f], hips: after.hips, highestHips: nextHighest, span: span, leg: leg) {
                            feetHold = false
                        }
                    }
                    guard feetHold else { continue }
                    let reach = distance(all[j], all[current]) / max(arm, 1e-6)
                    var c = reachCost * reach * reach
                    if st.last == mover { c += sameHandCost }
                    if all[next.leftHand].x > all[next.rightHand].x + 0.02 { c += crossCost }
                    if j == staying { c += matchCost }
                    c += costOfStanding(next)
                    let ns = State(p: next, last: mover)
                    let nd = d + c
                    if nd < (best[ns] ?? .infinity) {
                        best[ns] = nd
                        from[ns] = (st, Step(limb: mover == 0 ? .leftHand : .rightHand, to: j, match: j == staying))
                        open.append((nd, ns))
                    }
                }
            }
            // Feet: to any free hold below the hips within a leg's stretch,
            // or off to smear.
            for mover in 2...3 {
                let current = mover == 2 ? st.p.leftFoot : st.p.rightFoot
                var targets: [Int] = [-1]
                let handsMid = (all[st.p.leftHand].y + all[st.p.rightHand].y) / 2
                let highestHips = handsMid + arm * 0.25 + shape.torso * span
                for j in 0..<n where j != current && !occupied.contains(j) {
                    guard footReachable(all[j], hips: here.hips, highestHips: highestHips, span: span, leg: leg) else { continue }
                    targets.append(j)
                }
                for j in targets where j != current {
                    var next = st.p
                    if mover == 2 { next.leftFoot = j } else { next.rightFoot = j }
                    // Left foot stays left of the right foot.
                    if next.leftFoot >= 0, next.rightFoot >= 0, all[next.leftFoot].x > all[next.rightFoot].x { continue }
                    var c = footMoveCost
                    if j >= 0, current >= 0 {
                        let travel = distance(all[j], all[current]) / max(leg, 1e-6)
                        c += footReachCost * travel * travel
                    }
                    c += costOfStanding(next)
                    let ns = State(p: next, last: mover)
                    let nd = d + c
                    if nd < (best[ns] ?? .infinity) {
                        best[ns] = nd
                        from[ns] = (st, Step(limb: mover == 2 ? .leftFoot : .rightFoot, to: j, match: false))
                        open.append((nd, ns))
                    }
                }
            }
        }
        guard let goal else { return nil }
        var steps: [Step] = []
        var states: [Position] = [goal.p]
        var cursor = goal
        while let (prev, step) = from[cursor] {
            steps.append(step); states.append(prev.p); cursor = prev
        }
        steps.reverse(); states.reverse()
        var order: [Int] = []
        for p in states {
            for h in [p.leftHand, p.rightHand, p.leftFoot, p.rightFoot] where h >= 0 && !order.contains(h) { order.append(h) }
        }
        _ = isHandHold
        return Plan(steps: steps, order: order, states: states)
    }

    /// The plan said in words, one line per move, with the holds numbered
    /// in the order the plan first uses them.
    static func describe(_ plan: Plan, line: LineEngine.Line) -> [String] {
        func number(_ i: Int) -> Int { (plan.order.firstIndex(of: i) ?? i) + 1 }
        var out: [String] = []
        if let p = plan.states.first {
            var start = p.leftHand == p.rightHand
                ? "Start with both hands on \(number(p.leftHand))"
                : "Start with a hand on each of \(number(p.leftHand)) and \(number(p.rightHand))"
            let feet = [p.leftFoot, p.rightFoot].filter { $0 >= 0 }.map { "\(number($0))" }
            if !feet.isEmpty { start += ", feet on \(feet.joined(separator: " and "))" }
            out.append(start + ".")
        }
        for s in plan.steps {
            if s.limb.isHand {
                out.append(s.match ? "\(s.limb.name) matches on \(number(s.to))." : "\(s.limb.name) to \(number(s.to)).")
            } else {
                out.append(s.to < 0 ? "\(s.limb.name) comes off to smear." : "\(s.limb.name) to \(number(s.to)).")
            }
        }
        return out
    }

    /// The older entry, kept for the tests that build a stance from a list.
    static func stance(leftHand: CGPoint, rightHand: CGPoint, holds: [CGPoint],
                       handIndex: Int, span: Double, shape: Shape = .average) -> Pose {
        let feetFrom = holds.enumerated().filter { k, _ in k < handIndex - 1 || k > handIndex }.map(\.element)
        return stance(leftHand: leftHand, rightHand: rightHand, feetFrom: feetFrom, span: span, shape: shape)
    }

    /// - Parameter feet: where the feet are, when the planner has decided.
    ///   Nil on a side is a smear. Without it the feet are chosen here.
    static func stance(leftHand: CGPoint, rightHand: CGPoint, feetFrom: [CGPoint],
                       span: Double, shape: Shape = .average,
                       feet: (left: CGPoint?, right: CGPoint?)? = nil) -> Pose {
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
        // The highest the hips can go, with the arms bent as far as they
        // bend. A foot hold is reachable if it lies below that and within a
        // leg of wherever the hips end up; the hips then rise to meet it.
        let highestHips = mid.y + arm * 0.25 + shape.torso * span

        // Feet first, because the feet decide where the hips go. The highest
        // holds below the hips a leg can reach, one each side where possible,
        // never a hold a hand is on. A leg may take a hold a little past its
        // straight length, because the hips will come across to it.
        let leg = shape.leg * span
        let candidates = feetFrom.enumerated().filter { _, h in
            footReachable(h, hips: hips, highestHips: highestHips, span: span, leg: leg)
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
        if let feet {
            leftPick = feet.left.map { (offset: 0, element: $0) }
            rightPick = feet.right.map { (offset: 1, element: $0) }
        }

        // Weight over the feet. With feet on holds the hips come toward them,
        // as far as the arms allow the shoulders to follow.
        let onHolds = [leftPick, rightPick].compactMap { $0?.element }
        // Up over the feet. Hanging straight-armed the hips sit a torso
        // below the shoulders, which on a vertical wall puts every foot
        // hold above them. The arms bend instead: the hips rise until the
        // planted feet are within a leg, as far as the bend allows.
        if let lowest = onHolds.map({ $0.y - leg * 0.95 }).min(), lowest < hips.y {
            let raise = min(hips.y - lowest, hips.y - highestHips)
            if raise > 0 { neck.y -= raise; hips.y -= raise }
        }
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

    /// Whether a foot can be on a hold given where the hands put the body:
    /// below the highest the hips can rise, and within a leg's stretch of
    /// the hips wherever they settle between hanging and standing tall.
    static func footReachable(_ h: CGPoint, hips: CGPoint, highestHips: Double, span: Double, leg: Double) -> Bool {
        guard h.y - highestHips >= highestFoot * span else { return false }
        let settledY = min(max(h.y - leg * 0.95, highestHips), hips.y)
        return distance(h, CGPoint(x: hips.x, y: settledY)) <= leg * legStretch
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
