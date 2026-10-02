import Foundation
import CoreGraphics

/// The techniques a coach names that a fifteen-joint pose can actually see.
///
/// ## Where this comes from
///
/// Trace's findings were checked against thirteen technique sources, filed under
/// docs/technique-sources. Most of what those coaches teach falls into two
/// piles: things the existing findings already measure (bent arms, weight off
/// the feet, feet placed twice, hesitation, hanging outside the contacts), and
/// things no pose model can see (which part of the shoe is on the hold, how a
/// hand is gripping, a heel hook). This file is the third pile: faults the
/// coaches name, that the joints do show, that nothing here measured yet.
///
/// - Over-reaching. "We are naturally prone to over-reaching for handholds
///   instead of moving our feet up first" (Gresham, General approach). A reach
///   the arm made while both feet stayed exactly where they were.
/// - Square hips on a reach. "Our default setting is to climb with our hips
///   parallel and our arms bent" (Gresham); "keep one hip pushed up against
///   the wall" (REI). Hips square to the camera at launch and the arm bent at
///   the catch, on the same reach.
/// - Holding a lock-off. "Minimize holding lock-offs for longer than a few
///   seconds" (Gresham, Posture). A bent arm held still on its hold.
/// - Elbows flared. "Chicken-winging is when the elbows stick up high and out
///   from your torso" (Gresham, Posture). An elbow above its shoulder while the
///   hand is below it.
/// - High steps. "Several small steps are nearly always preferable to one big
///   one" (Gresham, Use of the toe). A foot landing near hip height.
///
/// ## What is deliberately not claimed
///
/// None of these can see the wall. A high step onto a rock-over is the move; a
/// gaston puts an elbow out on purpose; a lock-off turning a roof lip is
/// necessary. The thresholds are set so the finding needs a pattern, not one
/// event, and every message says what was measured so the climber can look at
/// the moment and disagree.
enum TechniqueEngine {

    struct Span {
        let start: Double
        let end: Double
        var duration: Double { max(0, end - start) }
    }

    /// One foot landing somewhere new.
    struct Step {
        let time: Double
        let ankle: JointID
        /// How far above the other foot it landed, in torso lengths. Nil when
        /// the other foot was not visible.
        let aboveOtherFoot: Double?
        /// How far below the hips it landed, in torso lengths. Negative means
        /// above them.
        let belowHips: Double?
        /// A throw followed within a second and a half. A high foot before a
        /// dynamic move is where the move comes from, not a fault.
        let beforeThrow: Bool

        /// Judged against the hips, not the other foot. A step big enough to
        /// count as a step at all already lands well above the standing foot,
        /// so that comparison flagged every step; "near hip height" is what
        /// the coaches say and what the climber can see.
        var isHigh: Bool {
            guard !beforeThrow, let b = belowHips else { return false }
            return b <= TechniqueEngine.highStepNearHips
        }
    }

    struct Reading {
        /// Reaches that went up, big enough to attribute between body and arm.
        let upwardReaches: [ReachEngine.Reach]
        /// Of those, the ones the arm made with both feet planted throughout.
        let feetStayed: [ReachEngine.Reach]
        /// Reaches where both the hips and the catching elbow could be read.
        let hipJudged: Int
        /// Of those, hips square at launch and the arm bent at the catch.
        let squareAndBent: [ReachEngine.Reach]
        /// Bent arms held still on their hold for longer than a few seconds.
        let lockOffs: [Span]
        /// Elbows held above their shoulder with the hand below.
        let flares: [Span]
        let steps: [Step]

        var highSteps: [Step] { steps.filter(\.isHigh) }

        /// Shares, or nil when there were too few events to make one.
        var feetStayedShare: Double? {
            guard upwardReaches.count >= minimumReaches else { return nil }
            return Double(feetStayed.count) / Double(upwardReaches.count)
        }
        var squareShare: Double? {
            guard hipJudged >= minimumReaches else { return nil }
            return Double(squareAndBent.count) / Double(hipJudged)
        }
        var highStepShare: Double? {
            guard steps.count >= minimumSteps else { return nil }
            return Double(highSteps.count) / Double(steps.count)
        }
        var longestLockOff: Span? { lockOffs.max { $0.duration < $1.duration } }
        var lockOffHeldSeconds: Double { longestLockOff?.duration ?? 0 }
        var flaredSeconds: Double { flares.reduce(0) { $0 + $1.duration } }
        var longestFlare: Span? { flares.max { $0.duration < $1.duration } }

        static let empty = Reading(upwardReaches: [], feetStayed: [], hipJudged: 0,
                                   squareAndBent: [], lockOffs: [], flares: [], steps: [])
    }

    // MARK: The judgements

    /// A hand has to gain this much height, in torso lengths, for the reach to
    /// be the kind a foot should have moved for.
    static let upwardRise = 0.4
    /// Below this share the arm made the reach; above it the body did, and
    /// the feet were doing their job whether or not they moved.
    static let armLed = 0.35
    /// A foot has to have landed somewhere new this long before the hand set
    /// off, or during the reach, for the feet to count as having moved.
    static let leadIn = 1.5
    /// Hip width at launch against this climber's widest. Above this they are
    /// square to the camera, which with the phone on the floor facing the wall
    /// means square to the wall.
    static let squareHips = 0.85
    /// And the catching elbow below this is an arm that did the work.
    static let bentCatch = 130.0
    /// A supporting arm below this angle is locked off rather than hanging.
    static let lockOffAngle = 110.0
    /// And the other arm has to be doing something else: reaching, or hanging
    /// straighter than this. Both arms bent and still at once is a bent-arm
    /// rest, which is the bent-arms finding's business; on the first real clip
    /// that shape was reported here as a three second lock-off and it was not
    /// one.
    static let otherArmHanging = 140.0
    /// Held for longer than this and it is a lock-off being held, which is the
    /// thing the coaches say to stop doing. "A few seconds".
    static let lockOffHeld = 2.5
    /// The elbow has to sit this far above the shoulder, in torso lengths,
    /// before it is flared rather than level.
    static let flareAbove = 0.08
    static let flareHeld = 1.0
    /// A foot landing within this of hip height, in torso lengths, is a high
    /// step. A straight standing leg puts the ankle about a torso below the
    /// hips and a knee-height step about half a torso below, so a third of a
    /// torso is past the knee and into the territory the coaches mean.
    static let highStepNearHips = 0.35
    /// A foot has to stay where it landed this long to have landed.
    static let stepSettle = 0.25
    /// And it cannot have come further than this, in torso lengths, in one
    /// step: a leg reaches about a torso and a half. On the real clip the
    /// tracker handed an ankle across to the other leg, a foot move of
    /// four torsos in a third of a second, and it was counted as a step.
    static let longestStep = 2.2
    /// Two feet cannot both land somewhere new within this of each other
    /// while climbing. On the first real clip that pair was the tracker
    /// handing an ankle from one leg to the other, which read as a foot
    /// leaping above the hips, and both landings are dropped rather than
    /// guessed between.
    static let swapWindow = 0.4
    /// An apex this soon after a landing means the foot was placed to throw
    /// from.
    static let throwLead = 1.5
    /// Fewer events than this and a share is not a share.
    static let minimumReaches = 3
    static let minimumSteps = 3
    /// A run may skip this many frames that fail the test and continue. One
    /// badly tracked frame in three seconds should not split a held position
    /// in two.
    static let tolerance = 3

    // MARK: Reading

    static func read(frames: [PoseFrame]) -> Reading {
        let usable = frames.filter { $0.com != nil }
        guard usable.count >= 8,
              let torso = MetricsEngine.medianTorso(usable), torso > 0.01
        else { return .empty }

        let steps = steps(in: usable, torso: torso)
        let reaches = ReachEngine.read(frames: usable)?.reaches ?? []

        var upward: [ReachEngine.Reach] = []
        var stayed: [ReachEngine.Reach] = []
        var judged = 0
        var square: [ReachEngine.Reach] = []
        for r in reaches {
            if let rise = rise(of: r, in: usable, torso: torso), rise >= upwardRise {
                upward.append(r)
                if r.share < armLed,
                   !steps.contains(where: { $0.time >= r.start - leadIn && $0.time <= r.end }) {
                    stayed.append(r)
                }
            }
            if let hips = r.hipOpenness, let elbow = r.catchElbow {
                judged += 1
                if hips >= squareHips, elbow < bentCatch { square.append(r) }
            }
        }

        var lockOffs: [Span] = []
        var flares: [Span] = []
        let arms = [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                    (JointID.rightShoulder, JointID.rightElbow, JointID.rightWrist)]
        let stillByWrist = Dictionary(uniqueKeysWithValues: arms.map {
            ($0.2, stillHand($0.2, in: usable, torso: torso))
        })
        for (k, (shoulder, elbow, wrist)) in arms.enumerated() {
            let still = stillByWrist[wrist]!
            let (oShoulder, oElbow, oWrist) = arms[1 - k]
            let otherStill = stillByWrist[oWrist]!
            lockOffs += spans(in: usable, minimum: lockOffHeld) { i in
                guard still[i],
                      let a = angle(usable[i], shoulder, elbow, wrist),
                      a >= MetricsEngine.plausibleElbow, a < lockOffAngle else { return false }
                // A lock-off, not a rest: the other hand is moving, or the
                // other arm is hanging long.
                if !otherStill[i] { return true }
                // An other arm that cannot be read, or reads as folded past
                // what an arm can do, is unknown rather than bent.
                guard let o = angle(usable[i], oShoulder, oElbow, oWrist),
                      o >= MetricsEngine.plausibleElbow else { return true }
                return o >= otherArmHanging
            }
            flares += spans(in: usable, minimum: flareHeld) { i in
                guard still[i],
                      let s = usable[i].pt(shoulder), let e = usable[i].pt(elbow),
                      let w = usable[i].pt(wrist) else { return false }
                // y grows downward, so above is smaller.
                return Double(s.y - e.y) / torso >= flareAbove && w.y >= s.y
            }
        }

        return Reading(upwardReaches: upward, feetStayed: stayed, hipJudged: judged,
                       squareAndBent: square, lockOffs: lockOffs, flares: flares,
                       steps: steps)
    }

    // MARK: Feet

    /// Every time a foot landed somewhere new: a planted run, a gap, and a
    /// planted run far enough from the last one to be a different hold. The
    /// same plant test the foot-precision finding uses, so a placement means
    /// one thing across the app; a landing close to the last one is that
    /// finding's business, not this one's.
    static func steps(in frames: [PoseFrame], torso: Double) -> [Step] {
        let planted = MetricsEngine.plantedFeet(frames: frames)
        let apexes = MetricsEngine.verticalApexes(path: frames.compactMap(\.com),
                                                  times: frames.map(\.time))
        var out: [Step] = []
        for ankle in [JointID.leftAnkle, JointID.rightAnkle] {
            let other: JointID = ankle == .leftAnkle ? .rightAnkle : .leftAnkle
            var runs: [(from: Int, to: Int)] = []
            var start: Int?
            for i in frames.indices {
                let on = planted[i].contains(ankle)
                if on, start == nil { start = i }
                if !on, let s = start { runs.append((s, i - 1)); start = nil }
            }
            if let s = start { runs.append((s, frames.count - 1)) }
            let runsWithTime = runs.filter {
                frames[$0.to].time - frames[$0.from].time >= MetricsEngine.footSettleSeconds
            }
            guard runsWithTime.count > 1 else { continue }
            for k in 1..<runsWithTime.count {
                let prev = runsWithTime[k - 1], next = runsWithTime[k]
                guard let a = frames[(prev.from + prev.to) / 2].pt(ankle),
                      let b = frames[(next.from + next.to) / 2].pt(ankle) else { continue }
                let moved = MetricsEngine.distance(a, b) / torso
                guard moved >= MetricsEngine.footAdjustDistance, moved <= longestStep,
                      frames[next.to].time - frames[next.from].time >= stepSettle
                else { continue }
                let f = frames[next.from]
                let above = f.pt(other).map { Double($0.y - b.y) / torso }
                let hips: Double? = {
                    guard let l = f.pt(.leftHip), let r = f.pt(.rightHip) else { return nil }
                    return Double(b.y - (l.y + r.y) / 2) / torso
                }()
                let thrown = apexes.contains { $0 - f.time > 0 && $0 - f.time <= throwLead }
                out.append(Step(time: f.time, ankle: ankle,
                                aboveOtherFoot: above, belowHips: hips,
                                beforeThrow: thrown))
            }
        }
        let sorted = out.sorted { $0.time < $1.time }
        return sorted.filter { step in
            !sorted.contains { $0.ankle != step.ankle && abs($0.time - step.time) <= swapWindow }
        }
    }

    // MARK: Helpers

    /// How much height the hand gained over the reach, in torso lengths.
    private static func rise(of r: ReachEngine.Reach, in frames: [PoseFrame],
                             torso: Double) -> Double? {
        guard let a = frames.first(where: { $0.time >= r.start })?.pt(r.hand),
              let b = frames.last(where: { $0.time <= r.end })?.pt(r.hand) else { return nil }
        return Double(a.y - b.y) / torso
    }

    /// Whether the hand was on something, frame by frame: moving slower than
    /// the settle speed the reach detector uses.
    private static func stillHand(_ wrist: JointID, in frames: [PoseFrame],
                                  torso: Double) -> [Bool] {
        var out = [Bool](repeating: false, count: frames.count)
        for i in 1..<frames.count {
            guard let a = frames[i - 1].pt(wrist), let b = frames[i].pt(wrist) else { continue }
            let dt = max(frames[i].time - frames[i - 1].time, 0.0005)
            out[i] = MetricsEngine.distance(a, b) / dt / torso < ReachEngine.settleSpeed
        }
        return out
    }

    /// Runs of frames passing `holds`, each at least `minimum` seconds long,
    /// allowing `tolerance` failing frames inside a run.
    static func spans(in frames: [PoseFrame], minimum: Double,
                      holds: (Int) -> Bool) -> [Span] {
        var out: [Span] = []
        var start: Int?
        var lastGood = 0
        var misses = 0
        func close() {
            if let s = start, frames[lastGood].time - frames[s].time >= minimum {
                out.append(Span(start: frames[s].time, end: frames[lastGood].time))
            }
            start = nil
            misses = 0
        }
        for i in frames.indices {
            if holds(i) {
                if start == nil { start = i }
                lastGood = i
                misses = 0
            } else if start != nil {
                misses += 1
                if misses > tolerance { close() }
            }
        }
        close()
        return out
    }

    private static func angle(_ f: PoseFrame, _ a: JointID, _ b: JointID, _ c: JointID) -> Double? {
        guard let p = f.pt(a), let q = f.pt(b), let s = f.pt(c) else { return nil }
        return MetricsEngine.angle(at: q, from: p, to: s)
    }
}
