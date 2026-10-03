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
    /// A foot will not come closer than this to hip height, in spans
    /// below the hips. On three real climbs, nine stances in ten kept
    /// every foot at least a quarter of a torso below the hips, and none
    /// put one above them.
    static let highestFoot = 0.08
    /// A leg can take a hold a little past its straight length, because the
    /// hips come across to meet it: a rock-over.
    static let legStretch = 1.25
    /// How far the hips move toward the feet when they are on holds, as a
    /// share of the gap. Weight over the feet, which is the thing every
    /// finding in this app is about. Measured on the app's own climber,
    /// the hips sat over one foot, about half a torso off the midpoint
    /// of the two; at 0.45 the figure's sat over the midpoint.
    static let hipsTowardFeet = 0.25
    /// Standing on planted feet, the hips sit between these shares of a
    /// leg above the lower foot: legs nearly straight, and a deep crouch.
    /// Real climbers at rest hold a knee at about a hundred and fifty
    /// degrees, which is a leg at 0.96 of its length.
    static let legsStraight = 0.96
    static let legsCrouched = 0.45
    /// How far above the top hand the shoulders may sit when standing
    /// with the hands held low, as a share of an arm: the hand at the
    /// collarbone. On the real climbs the top hand sat at most half a
    /// torso below the shoulders, and a hand at the chest is where a
    /// climber stands up to before reaching on.
    static let standingLift = 0.15

    /// The highest the hips can stand with these hands: the shoulders no
    /// more than `standingLift` above the top hand, and never more than an
    /// arm above the lower one, whose arm hangs to it.
    static func highestHips(leftHand: CGPoint, rightHand: CGPoint, arm: Double, torso: Double) -> Double {
        let top = min(leftHand.y, rightHand.y), lower = max(leftHand.y, rightHand.y)
        return max(top - arm * standingLift, lower - arm * 0.95) + torso
    }
    /// The torso leans from the hips toward the hands: the shoulders
    /// follow the hips toward the feet by this share of the hips' shift,
    /// and lean toward the higher hand by this share of its offset. The
    /// app's own climber leaned about twenty degrees on average.
    static let shouldersFollow = 0.5
    static let leanToReach = 0.6
    /// How far a drawn elbow or knee may fold, as the tightest angle it
    /// shows. A hand near its shoulder is an arm reaching forward to the
    /// wall, which from in front is a short arm, not a folded one: on the
    /// real footage an elbow at rest sat past a hundred degrees and a
    /// knee past ninety, and mid-move the elbow closed to about sixty.
    /// Past these the bones are drawn short. On five clips of the app's
    /// own climber, filmed from the floor, the elbow at rest sat at about
    /// a hundred and fifty with the lower quartile near a hundred and
    /// ten.
    static let tightestElbow = 110.0
    static let tightestKnee = 90.0
    /// Where a smeared foot goes when there is no hold for it.
    static let smearDrop = 0.44
    static let smearOut = 0.10
    /// How far above the mat a smearing foot stays, as a share of the
    /// picture's height.
    static let matClearance = 0.02

    // MARK: Reading

    static func read(line: LineEngine.Line, body: BodyProfile = .empty) -> Sequence? {
        read(line: line, shape: Shape(body))
    }

    /// A span is this share of a bouldering wall's height, at the least
    /// and at the most: a 1.7 metre reach on a wall of 3.5 to 4.5 metres.
    /// Sized from the gaps alone, a sparse route with long moves made a
    /// climber half the height of the wall.
    static let spanOverWall = 0.30...0.42

    /// - Parameter wallHeight: how much of the picture the wall takes, top
    ///   to mat, normalised. Nil when unknown, and the gaps alone decide.
    /// - Parameter mat: where the mat meets the wall, as a share of the
    ///   picture's height, when the wall was read. A foot never goes below
    ///   it: the feet start on the wall, not on the mat.
    static func read(line: LineEngine.Line, shape: Shape, wallHeight: Double? = nil, mat: Double? = nil) -> Sequence? {
        let hands = line.hands.map { CGPoint(x: $0.midX, y: $0.midY) }
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        guard hands.count >= 2 else { return nil }
        var gaps: [Double] = []
        for (a, b) in zip(hands, hands.dropFirst()) { gaps.append(distance(a, b)) }
        let median = LineEngine.medianOf(gaps)
        guard median > 1e-6 else { return nil }
        var span = median * spansPerGap
        if let wallHeight, wallHeight > 0.1 {
            span = min(max(span, wallHeight * spanOverWall.lowerBound), wallHeight * spanOverWall.upperBound)
        }

        let plan = self.plan(line: line, span: span, shape: shape, mat: mat)
        var stances: [Pose] = []
        if let plan {
            for p in plan.states {
                let aCenter = all[p.leftHand], bCenter = all[p.rightHand]
                let midpoint = CGPoint(x: (aCenter.x + bCenter.x) * 0.5,
                                       y: (aCenter.y + bCenter.y) * 0.5)
                let a = contactPoint(for: p.leftHand, center: aCenter, toward: midpoint, line: line)
                let b = contactPoint(for: p.rightHand, center: bCenter, toward: midpoint, line: line)
                let feetFrom = all.filter { $0 != aCenter && $0 != bCenter }
                let lf = p.leftFoot >= 0 ? all[p.leftFoot] : nil
                let rf = p.rightFoot >= 0 ? all[p.rightFoot] : nil
                stances.append(stance(leftHand: a.x <= b.x ? a : b, rightHand: a.x <= b.x ? b : a,
                                      feetFrom: feetFrom, span: span, shape: shape, feet: (lf, rf), mat: mat))
            }
        } else {
            // No plan: one hand at a time up the hand holds, feet by geometry.
            var pairs: [(CGPoint, CGPoint)] = []
            if line.startCount == 1 { pairs.append((hands[0], hands[0])) }
            for i in 1..<hands.count { pairs.append((hands[i - 1], hands[i])) }
            for (aCenter, bCenter) in pairs {
                let midpoint = CGPoint(x: (aCenter.x + bCenter.x) * 0.5,
                                       y: (aCenter.y + bCenter.y) * 0.5)
                let a = contactPoint(for: all.firstIndex { distance($0, aCenter) < 1e-6 } ?? -1,
                                     center: aCenter, toward: midpoint, line: line)
                let b = contactPoint(for: all.firstIndex { distance($0, bCenter) < 1e-6 } ?? -1,
                                     center: bCenter, toward: midpoint, line: line)
                let (l, r) = a.x <= b.x ? (a, b) : (b, a)
                let feetFrom = all.filter { $0 != aCenter && $0 != bCenter }
                stances.append(stance(leftHand: l, rightHand: r, feetFrom: feetFrom, span: span, shape: shape, mat: mat))
            }
        }
        return Sequence(stances: stances, plan: plan, span: span, shape: shape)
    }

    /// Put a hand on the usable part of the traced hold rather than always at
    /// its bounding-box centre. The planner still reasons about hold centres
    /// (which keeps its geometry stable), but the rendered body should visibly
    /// touch the plastic. For an outline we choose the point nearest the body's
    /// current centre; for old routes with no outline we retain the centre.
    private static func contactPoint(for index: Int, center: CGPoint,
                                     toward target: CGPoint, line: LineEngine.Line) -> CGPoint {
        guard line.outlines.indices.contains(index), !line.outlines[index].isEmpty else {
            return center
        }
        return line.outlines[index].min {
            distance($0, target) < distance($1, target)
        } ?? center
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
    /// A smeared foot costs this per stance. On a ladder every hand move
    /// needs a foot move, which is how people climb, and at a quarter a
    /// smear tied with the foot move and won: every plan smeared.
    /// Raised again from a half once the figure was measured against real
    /// footage: half the planned stances had a foot off the holds, and the
    /// climbers on film almost never did.
    static let smearCost = 1.0
    static let hipsOffCost = 1.2
    /// Hanging below the top hand further than a climber stands costs
    /// this per torso of extra drop. On three real climbs the hips sat a
    /// torso under the top hand, and past a torso and a half only when
    /// mid-move; the planner used to leave the feet low and dangle.
    static let hangCost = 0.8
    static let standingDrop = 1.5
    /// How far the hips may sit off the feet, in spans, before it costs.
    static let hipsLean = 0.12
    /// Raised from 0.15 once the figure was measured against the app's
    /// own climber: her hands were matched in fewer than one stance in
    /// ten, the planner's in one in four.
    static let matchCost = 0.5
    /// A hold this many times the width of the route's middle hand hold
    /// takes two hands: matching on it costs nothing, and a climber on a
    /// jug matches before the long reach rather than crossing through.
    static let jugWidth = 1.5
    static let footMoveCost = 0.2
    static let footReachCost = 0.3
    /// The most positions the search will look at before giving up and
    /// leaving the feet to geometry.
    static let searchLimit = 12_000
    /// How many of the nearest holds a limb considers at each step. A hand
    /// does not go to the far side of the wall when there are holds beside
    /// it, and considering every hold made a twenty-hold route a thirteen
    /// second search.
    static let nearestHands = 4
    static let nearestFeet = 3

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
    static func plan(line: LineEngine.Line, span: Double, shape: Shape, mat: Double? = nil) -> Plan? {
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        let handIndex = line.hands.compactMap { line.holds.firstIndex(of: $0) }
        let isHandHold = Set(handIndex)
        // The holds wide enough for both hands.
        let widths = handIndex.map { Double(line.holds[$0].width) }.sorted()
        let middleWidth = widths.isEmpty ? 0 : widths[widths.count / 2]
        let isJug = line.holds.map { Double($0.width) >= middleWidth * jugWidth }
        let n = all.count
        guard handIndex.count >= 2 else { return nil }
        let arm = shape.arm * span, leg = shape.leg * span

        // Start: the start holds, or the lowest hand hold and its neighbour.
        // Two hands always start on the start holds: one on each where
        // two are tagged, both on the one where one is. With more than two
        // tagged, which happens when a grade sticker and a start sticker
        // sit on different holds, the first two in the line are taken.
        var startL: Int, startR: Int
        switch line.startCount {
        case 2...: (startL, startR) = (handIndex[0], handIndex[1])
        case 1: (startL, startR) = (handIndex[0], handIndex[0])
        default:
            // The lowest hand hold that has another within reach. A lone
            // chip at the bottom, with nothing a hand could go to from
            // it, left the search with no move to make and no plan.
            // And one with something to stand on: a hold below it within a
            // leg. A climber does not start on the floor hanging from the
            // lowest chip; that chip is the first foot hold.
            func standable(_ i: Int) -> Bool {
                (0..<n).contains { $0 != i && all[$0].y > all[i].y + 0.02 && distance(all[$0], all[i]) <= leg * 1.6 }
            }
            var chosen: (Int, Int)?
            for strict in [true, false] where chosen == nil {
                for lowest in handIndex.sorted(by: { all[$0].y > all[$1].y }) where !strict || standable(lowest) {
                    let second = handIndex.filter { $0 != lowest }
                        .filter { distance(all[$0], all[lowest]) <= span * 0.95 && all[$0].y <= all[lowest].y + handDrop * span }
                        .min { distance(all[$0], all[lowest]) < distance(all[$1], all[lowest]) }
                    if let second { chosen = (lowest, second); break }
                }
            }
            if let chosen { (startL, startR) = chosen }
            else { let lowest = handIndex.min { all[$0].y > all[$1].y }!; (startL, startR) = (lowest, lowest) }
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
                           feet: (p.leftFoot >= 0 ? all[p.leftFoot] : nil, p.rightFoot >= 0 ? all[p.rightFoot] : nil),
                           mat: mat)
            poses[p] = q
            return q
        }
        func costOfStanding(_ p: Position, smears: Bool = true) -> Double {
            let q = pose(p)
            var c = 0.0
            if smears {
                if p.leftFoot < 0 { c += smearCost }
                if p.rightFoot < 0 { c += smearCost }
            }
            // Hips off the feet, past the bit of lean a body stands with
            // for free. Without the dead zone standing on one foot cost
            // more than smearing both, and every plan smeared.
            //
            // Judged against the feet that are on holds. A smeared foot is
            // drawn under the hips, so counting it made every smearing
            // stance look balanced and a planted foot off to one side look
            // worse than lifting it: on the real walls the search chose
            // three smears for every one it was forced into.
            let planted = [(p.leftFoot, q.leftFoot), (p.rightFoot, q.rightFoot)].filter { $0.0 >= 0 }.map { $0.1.x }
            if !planted.isEmpty {
                let feetX = planted.reduce(0, +) / Double(planted.count)
                c += hipsOffCost * max(0, min(1, abs(q.hips.x - feetX) / span) - hipsLean)
            }
            // Dangling: the hips further below the top hand than standing
            // puts them, which is feet left behind.
            let torso = shape.torso * span
            let dangle = (q.hips.y - min(q.leftHand.y, q.rightHand.y)) / torso - standingDrop
            c += hangCost * max(0, dangle)
            return c
        }

        // The feet at the start: where geometry would put them.
        let first = Position(leftHand: startL, rightHand: startR, leftFoot: -1, rightFoot: -1)
        let firstPose = stance(leftHand: all[startL], rightHand: all[startR],
                               feetFrom: all.filter { $0 != all[startL] && $0 != all[startR] }, span: span, shape: shape, mat: mat)
        func index(of point: CGPoint) -> Int { all.firstIndex { distance($0, point) < 1e-6 } ?? -1 }
        var origin = first
        if firstPose.leftFootHold != nil { origin.leftFoot = index(of: firstPose.leftFoot) }
        if firstPose.rightFootHold != nil { origin.rightFoot = index(of: firstPose.rightFoot) }

        // last: 0 lh, 1 rh, 2 lf, 3 rf, 4 none. run: how many times in a
        // row that hand has moved, so the third goes dearer than the second.
        struct State: Hashable { let p: Position; let last: Int; let run: Int }
        var best: [State: Double] = [:]
        var from: [State: (State, Step)] = [:]
        let start = State(p: origin, last: 4, run: 0)
        best[start] = 0
        var open = Heap<State>()
        open.push(0, start)
        var goal: State?
        var looked = 0
        while let (d, st) = open.pop(), looked < searchLimit {
            if d > (best[st] ?? .infinity) { continue }
            looked += 1
            if finishSet.contains(st.p.leftHand), finishSet.contains(st.p.rightHand) { goal = st; break }
            let here = pose(st.p)
            let occupied: Set<Int> = [st.p.leftHand, st.p.rightHand, st.p.leftFoot, st.p.rightFoot]

            // Hands.
            for mover in 0...1 {
                let current = mover == 0 ? st.p.leftHand : st.p.rightHand
                let staying = mover == 0 ? st.p.rightHand : st.p.leftHand
                let handTargets = handIndex.filter { j in
                    j != current && (j == staying || distance(all[j], all[staying]) <= span * 0.95)
                        && all[j].y <= all[current].y + handDrop * span
                }.sorted { distance(all[$0], all[current]) < distance(all[$1], all[current]) }.prefix(nearestHands)
                for j in handTargets {
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
                    let nextHighest = highestHips(leftHand: all[next.leftHand], rightHand: all[next.rightHand],
                                                  arm: arm, torso: shape.torso * span)
                    var feetHold = true
                    for f in [next.leftFoot, next.rightFoot] where f >= 0 {
                        if !footReachable(all[f], hips: after.hips, highestHips: nextHighest, span: span, leg: leg) {
                            feetHold = false
                        }
                    }
                    guard feetHold else { continue }
                    let reach = distance(all[j], all[current]) / max(arm, 1e-6)
                    var c = reachCost * reach * reach
                    // The same hand again costs more each time: once is a
                    // bump, twice is a lock-off held while the other arm
                    // does nothing, which the planner used to prefer.
                    let run = st.last == mover ? st.run + 1 : 0
                    if run > 0 { c += sameHandCost * Double(run * run) }
                    if all[next.leftHand].x > all[next.rightHand].x + 0.02 { c += crossCost }
                    if j == staying { c += isJug[j] ? matchCost / 2 : matchCost }
                    c += costOfStanding(next)
                    let ns = State(p: next, last: mover, run: min(run, 3))
                    let nd = d + c
                    if nd < (best[ns] ?? .infinity) {
                        best[ns] = nd
                        from[ns] = (st, Step(limb: mover == 0 ? .leftHand : .rightHand, to: j, match: j == staying))
                        open.push(nd, ns)
                    }
                }
            }
            // Feet: to any free hold below the hips within a leg's stretch,
            // or off to smear.
            for mover in 2...3 {
                let current = mover == 2 ? st.p.leftFoot : st.p.rightFoot
                var targets: [Int] = [-1]
                let highestHips = highestHips(leftHand: all[st.p.leftHand], rightHand: all[st.p.rightHand],
                                              arm: arm, torso: shape.torso * span)
                let reachable = (0..<n).filter { j in
                    j != current && !occupied.contains(j)
                        && footReachable(all[j], hips: here.hips, highestHips: highestHips, span: span, leg: leg)
                }
                let anchor = current >= 0 ? all[current] : here.hips
                targets += reachable.sorted { distance(all[$0], anchor) < distance(all[$1], anchor) }.prefix(nearestFeet)
                for j in targets where j != current {
                    var next = st.p
                    if mover == 2 { next.leftFoot = j } else { next.rightFoot = j }
                    // Left foot stays left of the right foot.
                    if next.leftFoot >= 0, next.rightFoot >= 0, all[next.leftFoot].x > all[next.rightFoot].x { continue }
                    // A foot move pays for its own effort and the stance's
                    // balance, not for smears: it is the thing that ends one.
                    var c = footMoveCost
                    if j >= 0, current >= 0 {
                        let travel = distance(all[j], all[current]) / max(leg, 1e-6)
                        c += footReachCost * travel * travel
                    }
                    c += costOfStanding(next, smears: false)
                    let ns = State(p: next, last: mover, run: 0)
                    let nd = d + c
                    if nd < (best[ns] ?? .infinity) {
                        best[ns] = nd
                        from[ns] = (st, Step(limb: mover == 2 ? .leftFoot : .rightFoot, to: j, match: false))
                        open.push(nd, ns)
                    }
                }
            }
        }
        // No way to the finish, which happens when the top hold is a speck
        // or sits out of reach of everything: the plan goes as high as the
        // search got, so the climber sees the sequence that exists rather
        // than nothing.
        let end: State
        if let goal { end = goal } else {
            guard let highest = best.keys.min(by: {
                let a = (all[$0.p.leftHand].y + all[$0.p.rightHand].y) / 2
                let b = (all[$1.p.leftHand].y + all[$1.p.rightHand].y) / 2
                return a != b ? a < b : (best[$0] ?? 0) < (best[$1] ?? 0)
            }), highest != start else { return nil }
            end = highest
        }
        var steps: [Step] = []
        var states: [Position] = [end.p]
        // A boulder is finished with both hands on the finish, whatever
        // the search managed: when it stopped short, the last moves go to
        // the finish anyway, as the throw they would be.
        var tail: [Step] = []
        var tailStates: [Position] = []
        if goal == nil {
            let finishes = finishSet.sorted { all[$0].x < all[$1].x }
            if let l = finishes.first {
                let r = finishes.count > 1 ? finishes[1] : l
                var p = end.p
                if p.leftHand != l { p.leftHand = l; if p.leftFoot == l { p.leftFoot = -1 }; if p.rightFoot == l { p.rightFoot = -1 }
                    tail.append(Step(limb: .leftHand, to: l, match: p.rightHand == l)); tailStates.append(p) }
                if p.rightHand != r { p.rightHand = r; if p.leftFoot == r { p.leftFoot = -1 }; if p.rightFoot == r { p.rightFoot = -1 }
                    tail.append(Step(limb: .rightHand, to: r, match: p.leftHand == r)); tailStates.append(p) }
            }
        }
        var cursor = end
        while let (prev, step) = from[cursor] {
            steps.append(step); states.append(prev.p); cursor = prev
        }
        steps.reverse(); states.reverse()
        steps += tail; states += tailStates
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
                       feet: (left: CGPoint?, right: CGPoint?)? = nil, mat: Double? = nil) -> Pose {
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
        // Hanging, the arms are straight. They were left eight per cent
        // short so they would not look locked, and with the elbow drawn
        // as a joint that slack bowed both arms out into a kite on every
        // matched hold.
        let drop = max(reach * 0.985, arm * 0.25)
        var neck = CGPoint(x: mid.x, y: mid.y + drop)
        var hips = CGPoint(x: mid.x, y: neck.y + shape.torso * span)
        // The highest the hips can go: standing on the feet with the hands
        // held low. A foot hold is reachable if it lies below that and
        // within a leg of wherever the hips end up.
        let highestHips = Self.highestHips(leftHand: leftHand, rightHand: rightHand,
                                           arm: arm, torso: shape.torso * span)

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
        // Standing. Hanging straight-armed put the hips a torso under the
        // shoulders whatever the feet were doing, so a climber with both
        // hands on a waist-high start jug hung below it with the legs flat
        // on the mat. With feet planted the hips stand as tall as the legs
        // and the arms both allow; the arms then angle to the hands, above
        // the shoulders or below them. Only when no stance on the feet
        // brings a hand within reach does the body hang from the hands.
        //
        // Tall, not low. This used to take the lowest point the legs and
        // arms both allowed, and measured against three real climbs the
        // figure was a sitting hang: hips nearly two torsos under the top
        // hand, knees at ninety degrees, feet under the hips. The climbers
        // stood with their hips a torso under the top hand, knees near a
        // hundred and fifty degrees and their feet a leg below them.
        if let lowFoot = onHolds.map(\.y).max(), let highFoot = onHolds.map(\.y).min() {
            let torso = shape.torso * span
            // What the legs allow: no higher than a straight leg from the
            // lower foot, no lower than a deep crouch over the higher one.
            // What the arms allow: from hanging straight to standing with
            // the hands at the waist. Where the two overlap the hips take
            // the lowest point in both, the arms as straight as the legs
            // let them be. Where they do not, the arms decide. Hands far
            // above the feet: the body hangs, and a foot left out of reach
            // is the planner's to move. A foot too high for any crouch
            // under the hands, a high step: the arms bend as far as they
            // bend and the hips go as high as that allows, the foot a
            // little above them.
            let legsHigh = lowFoot - leg * legsStraight, legsLow = highFoot - leg * legsCrouched
            let armsHigh = highestHips, armsLow = hips.y
            let high = max(legsHigh, armsHigh), low = min(legsLow, armsLow)
            var target = high <= low ? high : (legsLow < armsHigh ? armsHigh : armsLow)
            // And never with a foot more than a high step above the hips:
            // the hips come up over it, the hands lower on the body.
            target = min(target, highFoot - highestFoot * span)
            hips.y = target
            neck.y = target - torso
        }
        if !onHolds.isEmpty {
            let feetX = onHolds.map(\.x).reduce(0, +) / Double(onHolds.count)
            var dx = (feetX - hips.x) * hipsTowardFeet
            let used = max(distance(leftHand, CGPoint(x: neck.x - half, y: neck.y)),
                           distance(rightHand, CGPoint(x: neck.x + half, y: neck.y)))
            let limit = max(0, arm - used)
            dx = min(max(dx, -limit), limit)
            // The hips go over the feet; the shoulders follow only part of
            // the way, so the torso leans from the feet toward the hands,
            // as a climber's does.
            neck.x += dx * shouldersFollow; hips.x += dx
        }
        // And toward the reach: the shoulders come across under the
        // higher hand, as far as the other arm allows.
        do {
            let higher = leftHand.y <= rightHand.y ? leftHand : rightHand
            let lower = leftHand.y <= rightHand.y ? rightHand : leftHand
            var shift = (higher.x - neck.x) * leanToReach
            let lowerShoulderX = neck.x + (lower.x <= neck.x ? -half : half)
            let room = max(0, arm - distance(lower, CGPoint(x: lowerShoulderX, y: neck.y)))
            shift = min(max(shift, -room), room)
            neck.x += shift
        }
        // A smear is on the wall, not the mat: no lower than the route's
        // lowest hold, a little past it. At the start the smearing leg
        // used to reach down off the bottom of the photograph. And never
        // on the mat itself, where the mat was read: the feet start on
        // the wall whatever the hands are on.
        var lowestY: Double = max(leftHand.y, rightHand.y)
        for h in feetFrom where h.y > lowestY { lowestY = h.y }
        let floorY: Double = min(lowestY + 0.03, mat.map { $0 - matClearance } ?? 1)
        let leastSmear = smearDrop * span * 0.35
        // Hips pinched against the mat by a smear rise with the foot, so
        // the foot stays a short leg below them: a crouch, not a foot
        // beside the hips.
        if leftPick == nil || rightPick == nil, hips.y + leastSmear > floorY {
            let lift = hips.y + leastSmear - floorY
            hips.y -= lift; neck.y -= lift
        }

        let ls = CGPoint(x: neck.x - half, y: neck.y)
        let rs = CGPoint(x: neck.x + half, y: neck.y)
        let head = CGPoint(x: neck.x, y: neck.y - shape.headRadius * span * 1.6)

        // Joints by two bones: an arm shorter than its reach bends, and
        // the elbow sits where the upper arm and forearm meet, outward
        // from the body and down. A straight arm bows out a hair so it
        // still reads as an arm and not a line.
        func joint(_ from: CGPoint, _ to: CGPoint, bone: Double, out: Double, lean: Double, tightest: Double) -> CGPoint {
            let d = distance(from, to)
            let m = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            guard d > 1e-6 else { return CGPoint(x: m.x + out * span * 0.04, y: m.y) }
            let ux = (to.x - from.x) / d, uy = (to.y - from.y) / d
            let folded = max(0, bone * bone - (d / 2) * (d / 2)).squareRoot()
            // No tighter than the tightest angle: the fold is capped, and
            // the limb reads as reaching away from the viewer.
            let cap = (d / 2) / tan(tightest / 2 * .pi / 180)
            let h = min(max(span * 0.025, min(folded, cap)), cap)
            // The two perpendiculars; take the one pointing outward and
            // the way this joint bends.
            let a = (x: -uy, y: ux), b = (x: uy, y: -ux)
            let score = { (p: (x: Double, y: Double)) in p.x * out + p.y * lean }
            let pick = score(a) >= score(b) ? a : b
            return CGPoint(x: m.x + pick.x * h, y: m.y + pick.y * h)
        }
        func elbow(_ hand: CGPoint, _ shoulder: CGPoint, out: Double) -> CGPoint {
            joint(shoulder, hand, bone: arm / 2, out: out, lean: 0.6, tightest: tightestElbow)
        }

        func foot(_ pick: (offset: Int, element: CGPoint)?, side: Double) -> (CGPoint, Int?) {
            if let pick { return (pick.element, pick.offset) }
            // But always under the hips, by at least a short leg.
            let drop = hips.y + smearDrop * span
            let least = hips.y + leastSmear
            return (CGPoint(x: hips.x + side * smearOut * span, y: max(min(drop, floorY), least)), nil)
        }
        let (lf, lfi) = foot(leftPick, side: -1)
        let (rf, rfi) = foot(rightPick, side: 1)

        // Knees bend out to the side and up, the frog of a climber's legs.
        func knee(_ f: CGPoint, side: Double) -> CGPoint {
            joint(hips, f, bone: leg / 2, out: side, lean: -0.5, tightest: tightestKnee)
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

    /// A binary min-heap on cost. The search used to sort its whole open
    /// list on every pop, which on a twenty-hold route was six seconds.
    struct Heap<T> {
        private var items: [(Double, T)] = []
        var isEmpty: Bool { items.isEmpty }
        mutating func push(_ cost: Double, _ item: T) {
            items.append((cost, item))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard items[i].0 < items[parent].0 else { break }
                items.swapAt(i, parent); i = parent
            }
        }
        mutating func pop() -> (Double, T)? {
            guard !items.isEmpty else { return nil }
            let top = items[0]
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < items.count, items[l].0 < items[m].0 { m = l }
                    if r < items.count, items[r].0 < items[m].0 { m = r }
                    guard m != i else { break }
                    items.swapAt(i, m); i = m
                }
            }
            return top
        }
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
