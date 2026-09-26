import Foundation
import CoreGraphics

/// Everything in here is arithmetic on a joint time series. No machine learning
/// beyond the pose model itself.
///
/// All of it is beta-agnostic by construction: nothing reads the wall, the holds,
/// or the sequence. It measures how well you executed whatever you chose to do.
enum MetricsEngine {

    /// COM speed below this counts as "still", in torso lengths per second.
    ///
    /// Body-relative, because a normalized unit is a fraction of the frame and
    /// not a length. The same climber filmed from twice as far away moves at
    /// half the speed in image units, and a fixed threshold therefore calls
    /// them still twice as often. On the first real clip Trace was shown, a
    /// climber filling a fifth of the frame, the old absolute 0.035 units per
    /// second counted 28% of the ascent as standing still; the same number
    /// expressed against their own torso counts 11%, which is what a person
    /// watching the clip would say.
    ///
    /// The value is what the old constant worked out to at the scale everything
    /// was tuned against: the fixtures put a 0.20 torso in frame, and
    /// 0.035 / 0.20 is 0.175. So this changes nothing about a climber filmed
    /// the way the synthetic ones were, and fixes every other distance.
    static let stillTorsoPerSecond = 0.175

    /// The threshold in image units for a climber of this torso length.
    static func stillSpeed(torso: Double) -> Double { torso * stillTorsoPerSecond }

    /// What to use when there is no torso to measure against.
    ///
    /// Only a frame with no hips in it lands here, which on a real clip means
    /// the tracker lost the body, and in a test means a fixture built out of
    /// one limb. It is the old absolute constant: not right, but the thing that
    /// was there before, and better than treating a scaleless body as still or
    /// as moving by fiat.
    static let stillSpeedWithoutABody = 0.035

    static func stillSpeed(of frames: [PoseFrame]) -> Double {
        medianTorso(frames).map { $0 > 0.02 ? stillSpeed(torso: $0) : stillSpeedWithoutABody }
            ?? stillSpeedWithoutABody
    }
    /// A still stretch longer than this is a pause worth mentioning.
    private static let pauseSeconds = 0.8
    /// Wrist speed above this counts as a hand being thrown rather than
    /// adjusted, in torso lengths per second. Body-relative for the same reason
    /// `stillTorsoPerSecond` is, and the same value the old absolute 0.25 came
    /// to at the scale the fixtures are drawn at.
    static let reachTorsoPerSecond = 1.25
    /// A hand has to travel this far to count as having gone to a new hold.
    /// And it has to end up somewhere: this far from where it set off, in torso
    /// lengths.
    static let reachTorsoDistance = 0.25
    /// A hand contact further than this from any apex was not a dynamic move.
    private static let deadpointWindow = 0.6

    /// Net displacement below which a path ratio says nothing, in image units.
    /// Roughly a third of a tracked body length at typical framing.
    /// Net displacement, in torso lengths, below which the path ratio means
    /// nothing. In torso lengths rather than image units, so it does not depend
    /// on how far away the phone was, and set where it is because a climb that
    /// ends two and a half body lengths from where it started is the shortest
    /// one where "further than the straight line" is a fair question.
    static let minimumTravel = 2.5

    /// Everything up to the high point of the climb.
    ///
    /// The clip is not the climb. It keeps running while you top out and sit
    /// there, while you downclimb, and while you drop off and walk away, and
    /// none of that is climbing. Measured over the whole clip a boulder that
    /// finishes near where it started has almost no net displacement, so the
    /// path ratio divides by nearly nothing and reports that the hips traveled
    /// five hundred percent further than the straight line. The descent also
    /// contributes pauses you did not take, foot placements you did not make,
    /// and a round trip the size of the route.
    ///
    /// So the analysis runs on the ascent, and it ends at the high point.
    ///
    /// No tail. Every frame past the top is the body on its way down, and on a
    /// dead straight climb even a third of a second of that puts thirty percent
    /// on the path ratio, which is the number this trim exists to protect.
    ///
    /// Where the top is, and when the body first got there, are both decided
    /// against noise rather than against one sample.
    ///
    /// The lowest single y is whichever frame the tracker misplaced furthest
    /// upward, so the top is taken as a low percentile instead: a handful of
    /// spiked frames cannot move it. The cut is then the first frame within a
    /// tenth of a torso length of that, because anything that close has got
    /// there and the rest is settling.
    static let ascentTop = 0.10
    static let topPercentile = 0.02

    static func ascent(_ frames: [PoseFrame]) -> [PoseFrame] {
        let usable = frames.filter { $0.com != nil }
        guard usable.count >= 4,
              let torso = medianTorso(usable), torso > 0.01
        else { return frames }

        let heights = usable.map { $0.com!.y }.sorted()
        let peak = heights[min(heights.count - 1,
                               Int(Double(heights.count) * topPercentile))]

        var kept: [PoseFrame] = []
        for f in frames {
            kept.append(f)
            if let com = f.com, (com.y - peak) / torso <= ascentTop { break }
        }
        // Never trim away so much that there is nothing left to read.
        return kept.count >= 4 ? kept : frames
    }

    static func compute(frames all: [PoseFrame]) -> Metrics {
        let frames = ascent(all)
        let tracked = frames.filter { $0.meanConfidence > 0 && $0.com != nil }
        let confidence = frames.isEmpty ? 0 : Double(tracked.count) / Double(frames.count)
        let duration = (frames.last?.time ?? 0) - (frames.first?.time ?? 0)

        let path = tracked.compactMap { $0.com }
        let times = tracked.map { $0.time }

        let length = pathLength(path)
        let straight = (path.first != nil && path.last != nil)
            ? distance(path.first!, path.last!) : 0
        let stops = pauses(path: path, times: times, torso: medianTorso(tracked) ?? 0.2)

        return Metrics(
            entropy: geometricEntropy(path: path, length: length),
            logJerk: logDimensionlessJerk(path: path, times: times, length: length),
            // A traverse ends near where it started, so the straight line is
            // almost nothing and the ratio runs away. Below a few body lengths
            // of net travel the number is not about wandering, it is about the
            // climb not going anywhere, so it is not reported at all.
            pathRatio: netTravel(path, frames: tracked) >= minimumTravel ? length / straight : 0,
            staticElbowAngle: staticElbow(frames: tracked, times: times),
            pauseCount: stops.count,
            pauseTotal: stops.reduce(0) { $0 + ($1.end - $1.start) },
            footAdjustments: footAdjustments(frames: tracked),
            comOffsetFromFeet: comOffsetFromFeet(frames: tracked, times: times),
            deadpointOffsets: deadpointOffsets(frames: tracked, times: times),
            comPath: path,
            duration: duration,
            trackingConfidence: confidence,
            bracketedFraction: ForceEngine.bracketedFraction(frames: tracked),
            compressionFraction: ForceEngine.compressionFraction(frames: tracked),
            swingTotal: ForceEngine.swingTotal(frames: tracked),
            moveWaste: MoveEngine.read(frames: tracked)?.waste,
            movingJerk: movingJerk(frames: tracked)
        )
    }

    // MARK: - Weight on arms rather than feet
    //
    // How far the center of mass sits sideways of the feet, in torso lengths, while
    // the climber is not moving. Normalizing by torso length is what makes it
    // independent of how far away the phone was.
    //
    // Note this is a projection, so it means different things at different camera
    // angles. Filmed side on, which is what Trace asks for, it reads as hips
    // hanging away from the wall. Filmed front on it reads as a barn door.

    static func comOffsetFromFeet(frames: [PoseFrame], times: [Double]) -> Double {
        let path = frames.compactMap { $0.com }
        let speeds = speedSeries(path: path, times: times)
        let still = stillSpeed(of: frames)
        var samples: [Double] = []

        for (i, frame) in frames.enumerated() {
            guard i < speeds.count, speeds[i] < still,
                  let com = frame.com,
                  let base = baseOfSupport(frame),
                  let torso = torsoLength(frame), torso > 0.02 else { continue }
            samples.append(abs(Double(com.x) - base) / torso)
        }
        // One frame of near-stillness is not a measurement of how someone rests.
        // Below roughly half a second of it there is nothing to report.
        guard samples.count >= Self.minimumStillSamples else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    /// Frames of near-stillness needed before the offset is reported at all.
    /// Roughly half a second at thirty frames a second.
    static let minimumStillSamples = 15

    /// Midpoint of whichever ankles are visible.
    static func baseOfSupport(_ f: PoseFrame) -> Double? {
        let ankles = [f.pt(.leftAnkle), f.pt(.rightAnkle)].compactMap { $0 }
        guard !ankles.isEmpty else { return nil }
        return ankles.reduce(0.0) { $0 + Double($1.x) } / Double(ankles.count)
    }

    /// Shoulder midpoint to hip midpoint. The body-scale reference.
    static func torsoLength(_ f: PoseFrame) -> Double? {
        guard let ls = f.pt(.leftShoulder), let rs = f.pt(.rightShoulder),
              let lh = f.pt(.leftHip), let rh = f.pt(.rightHip) else { return nil }
        let shoulders = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let hips = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        return distance(shoulders, hips)
    }

    // MARK: - Deadpoint timing
    //
    // On a dynamic move the body is briefly weightless at the top of its arc. A hand
    // that arrives at that apex catches a hold for free. A hand that arrives early is
    // still driving upward, and one that arrives late is already falling back onto
    // its own arms. Either way you pay for the mistiming.
    //
    // Returned signed, in seconds: negative is early, positive is late.

    static func deadpointOffsets(frames: [PoseFrame], times: [Double]) -> [Double] {
        let path = frames.compactMap { $0.com }
        guard path.count > 6, times.count == path.count else { return [] }

        let apexes = verticalApexes(path: path, times: times)
        guard !apexes.isEmpty else { return [] }

        var offsets: [Double] = []
        for wrist in [JointID.leftWrist, JointID.rightWrist] {
            for contact in handContacts(frames: frames, times: times, joint: wrist) {
                guard let apex = apexes.min(by: {
                    abs($0 - contact) < abs($1 - contact)
                }) else { continue }
                let offset = contact - apex
                // A hand that landed nowhere near an apex was a static move, not a
                // mistimed dynamic one, so it is not evidence either way.
                if abs(offset) <= deadpointWindow { offsets.append(offset) }
            }
        }
        return offsets
    }

    /// Moments where the center of mass stopped rising. In image coordinates y grows
    /// downward, so rising means a negative vertical velocity.
    ///
    /// An apex is only an apex if something was thrown. The first version of this
    /// tested the sign of the vertical velocity alone, which on real footage fires
    /// on every micro-wobble at 30 frames a second: a thirteen second boulder came
    /// back with most of its frames labeled deadpoint. Three gates fix that.
    ///
    /// The rise has to be fast enough to be a move rather than noise; it has to
    /// have lasted, so that a single jittery frame cannot qualify; and the climber
    /// has to have actually gained height across the launch. A climber standing
    /// still now produces no apexes at all, which is the correct answer.
    static let launchSpeed = 0.12        // image units per second, upward
    static let launchSeconds = 0.10      // how long the rise must hold
    static let launchRise = 0.012        // height actually gained, image units

    static func verticalApexes(path: [CGPoint], times: [Double]) -> [Double] {
        guard path.count > 2, times.count == path.count else { return [] }
        var out: [Double] = []

        // Rising is a *fall* in y, so an upward velocity is negative. Flip it here
        // once so the rest of this reads in the direction a climber thinks in.
        var up = [Double](repeating: 0, count: path.count)
        for i in 1..<path.count {
            let dt = max(times[i] - times[i - 1], 0.0005)
            up[i] = Double(path[i - 1].y - path[i].y) / dt
        }

        var riseStart: Int?
        for i in 1..<path.count {
            if up[i] > Self.launchSpeed {
                if riseStart == nil { riseStart = i }
                continue
            }
            // The rise just ended. Was it a launch, or was it noise?
            guard let start = riseStart else { continue }
            riseStart = nil
            let held = times[i] - times[start]
            let gained = Double(path[start].y - path[i].y)
            guard held >= Self.launchSeconds, gained >= Self.launchRise else { continue }
            out.append(times[i])
        }
        return out
    }

    /// Times at which a hand was thrown somewhere new and then settled.
    ///
    /// One threshold used to decide both halves, so a single throw crossed it
    /// several times and was reported as several reaches: thirty-six of them in
    /// a thirty-second climb containing nine, six inside half a second of each
    /// other. That inflated the deadpoint count and made per-move readings
    /// meaningless. `ReachEngine` owns the definition now, with a launch speed,
    /// a lower settle speed, and a settle that has to hold, so the app has one
    /// idea of what a hand move is rather than two.
    static func handContacts(frames: [PoseFrame], times: [Double], joint: JointID) -> [Double] {
        guard let torso = medianTorso(frames), torso > 0.02 else { return [] }
        return ReachEngine.settles(of: joint, in: frames, torso: torso)
            .compactMap { $0.to < times.count ? times[$0.to] : nil }
    }

    // MARK: - Geometric entropy
    //
    // H = ln(2L / C), where L is the length of the COM path and C is the perimeter
    // of its convex hull. The established climbing-specific efficiency measure: it
    // falls as a climber learns a route, and it tracks measured energy cost.

    static func geometricEntropy(path: [CGPoint], length: Double) -> Double {
        guard path.count >= 3, length > 0 else { return 0 }
        let hull = convexHull(path)
        let perimeter = pathLength(hull + [hull.first].compactMap { $0 })
        guard perimeter > 0.0001 else { return 0 }
        return log(2 * length / perimeter)
    }

    /// Andrew's monotone chain.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func build(_ pts: [CGPoint]) -> [CGPoint] {
            var out: [CGPoint] = []
            for p in pts {
                while out.count >= 2, cross(out[out.count - 2], out[out.count - 1], p) <= 0 {
                    out.removeLast()
                }
                out.append(p)
            }
            out.removeLast()
            return out
        }
        return build(sorted) + build(sorted.reversed())
    }

    // MARK: - Smoothness
    //
    // Log dimensionless jerk. Third derivative of COM position, normalized by
    // duration and path length so clips of different lengths compare. Lower is
    // smoother. Comparable within one capture setup, not across setups.

    /// Log dimensionless jerk, computed on a path resampled to a fixed rate.
    ///
    /// Jerk is a third derivative, so finite differencing multiplies the tracker's
    /// own noise by roughly one over the frame interval cubed. Left at the
    /// capture rate, the same climb filmed at 60fps scores very differently from
    /// one filmed at 30, and the difference is all noise. Resampling first is
    /// what makes two of your own attempts comparable at all.
    ///
    /// The number that comes out is still dominated by the noise floor rather
    /// than by you, which is why nothing in the app judges it against a fixed
    /// threshold. It is only ever compared against your own other attempts.
    static let jerkRate = 30.0

    static func logDimensionlessJerk(path: [CGPoint], times: [Double], length: Double) -> Double {
        guard path.count > 6, length > 0.001, times.count == path.count else { return 0 }
        let T = times.last! - times.first!
        guard T > 0.3 else { return 0 }

        let series = resample(path: path, times: times, rate: Self.jerkRate)
        guard series.count > 6 else { return 0 }
        let dt = 1.0 / Self.jerkRate

        func derive(_ s: [CGPoint]) -> [CGPoint] {
            guard s.count > 1 else { return [] }
            return (1..<s.count).map {
                CGPoint(x: (s[$0].x - s[$0 - 1].x) / dt, y: (s[$0].y - s[$0 - 1].y) / dt)
            }
        }
        let jerk = derive(derive(derive(series)))
        guard !jerk.isEmpty else { return 0 }

        let integral = jerk.reduce(0.0) { $0 + ($1.x * $1.x + $1.y * $1.y) * dt }
        guard integral > 0 else { return 0 }

        let dimensionless = pow(T, 5) / (length * length) * integral
        return log(max(dimensionless, 1e-9))
    }

    /// Smoothness measured one move at a time.
    ///
    /// Log dimensionless jerk multiplies the jerk integral by the fifth power
    /// of the duration and divides by the square of the path length. A rest
    /// adds to the duration and nothing to the length, so the same movement
    /// with a pause dropped into the middle of it scored as far rougher than
    /// the same movement without one. Trace then raised two findings off one
    /// behaviour: start-stop movement, because the number was high, and
    /// reading the route while hanging on it, because of the rest that made it
    /// high. One flaw, counted twice, and the second count was an artefact of
    /// the formula.
    ///
    /// The measure was built for a single discrete movement, so it is applied
    /// to single movements: each of the moves Trace already splits the climb
    /// into, with the middle value taken. Cutting at the rests instead was not
    /// enough, because a rest then splits one long span into two short ones and
    /// the measure is sensitive to duration in exactly that way. The move is
    /// the only unit that stays the same size whether somebody rested or not.
    ///
    /// Nil when there were too few moves to read, which is not the same as a
    /// climb that flowed.
    static func movingJerk(frames: [PoseFrame]) -> Double? {
        guard let reading = MoveEngine.read(frames: frames) else { return nil }
        let usable = frames.filter { $0.com != nil }
        var values: [Double] = []
        for move in reading.moves {
            let slice = usable.filter { $0.time >= move.start && $0.time <= move.end }
            let path = slice.compactMap { $0.com }
            guard path.count > 6 else { continue }
            let value = logDimensionlessJerk(path: path, times: slice.map(\.time),
                                             length: pathLength(path))
            // Zero is the guard inside that function saying the move was too
            // short to read, not a perfectly smooth one.
            if value != 0 { values.append(value) }
        }
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Linear resampling of a path onto an even grid.
    static func resample(path: [CGPoint], times: [Double], rate: Double) -> [CGPoint] {
        guard path.count > 1, times.count == path.count, rate > 0 else { return path }
        let start = times.first!, end = times.last!
        guard end > start else { return path }

        let count = Int(((end - start) * rate).rounded()) + 1
        guard count > 1, count < 100_000 else { return path }

        var out: [CGPoint] = []
        out.reserveCapacity(count)
        var j = 0
        for i in 0..<count {
            let t = start + Double(i) / rate
            while j < times.count - 2 && times[j + 1] < t { j += 1 }
            let t0 = times[j], t1 = times[j + 1]
            let span = t1 - t0
            let u = span > 0 ? min(max((t - t0) / span, 0), 1) : 0
            out.append(CGPoint(x: path[j].x + (path[j + 1].x - path[j].x) * u,
                               y: path[j].y + (path[j + 1].y - path[j].y) * u))
        }
        return out
    }

    // MARK: - Bent arms while static
    //
    // The most common and most expensive leak. Biceps holding a load the skeleton
    // would hold for free. Only counted while the COM is near-still, because a bent
    // arm mid-pull is just pulling.

    /// Mean elbow angle across the frames given, with no stillness gate.
    ///
    /// `staticElbow` only looks at frames where the center of mass was near
    /// still, which is right for the leak but wrong for a window around a fall:
    /// during a fall nobody is still, and gating on it would return the default
    /// of 180 and read as perfectly straight arms.
    static func meanElbow(frames: [PoseFrame]) -> Double? {
        var angles: [Double] = []
        for frame in frames {
            for side in [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                         (JointID.rightShoulder, JointID.rightElbow, JointID.rightWrist)] {
                guard let sh = frame.pt(side.0), let e = frame.pt(side.1), let w = frame.pt(side.2)
                else { continue }
                angles.append(angle(at: e, from: sh, to: w))
            }
        }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / Double(angles.count)
    }

    static func staticElbow(frames: [PoseFrame], times: [Double]) -> Double {
        let speeds = speedSeries(path: frames.compactMap { $0.com }, times: times)
        let still = stillSpeed(of: frames)
        var angles: [Double] = []

        for (i, frame) in frames.enumerated() {
            guard i < speeds.count, speeds[i] < still else { continue }
            for side in [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                         (JointID.rightShoulder, JointID.rightElbow, JointID.rightWrist)] {
                guard let s = frame.pt(side.0), let e = frame.pt(side.1), let w = frame.pt(side.2)
                else { continue }
                angles.append(angle(at: e, from: s, to: w))
            }
        }
        guard !angles.isEmpty else { return 180 }
        return angles.reduce(0, +) / Double(angles.count)
    }

    // MARK: - Pauses

    struct Pause { var start: Double; var end: Double }

    /// `torso` is the climber's torso length in image units, so "still" means
    /// the same thing however far away the phone was.
    static func pauses(path: [CGPoint], times: [Double], torso: Double) -> [Pause] {
        let speeds = speedSeries(path: path, times: times)
        let still = stillSpeed(torso: torso)
        var out: [Pause] = []
        var runStart: Double?

        for (i, s) in speeds.enumerated() {
            let t = i < times.count ? times[i] : 0
            if s < still {
                if runStart == nil { runStart = t }
            } else if let start = runStart {
                if t - start >= pauseSeconds { out.append(Pause(start: start, end: t)) }
                runStart = nil
            }
        }
        if let start = runStart, let last = times.last, last - start >= pauseSeconds {
            out.append(Pause(start: start, end: last))
        }
        return out
    }

    // MARK: - Foot precision
    //
    // A foot that lands, shifts, and lands again near where it was. High counts
    // mean you are not looking at your feet.
    //
    // The first version of this counted 41 adjustments in a thirteen second
    // boulder, which is three a second, and it was counting the tracker rather
    // than the climber. Three things were wrong with it. It compared a raw
    // frame-to-frame distance against a fixed number, so a climber filmed twice
    // as far away was judged twice as sensitively. It had a single threshold, so
    // ankle jitter sitting right on that threshold toggled the state on every
    // frame. And it never checked how far the foot actually went, so a genuine
    // move to a new hold counted the same as a two centimetre shuffle.
    //
    // This version fixes all three: every distance is in torso lengths, moving
    // and settled have separate thresholds with a gap between them, and an
    // excursion only counts when the foot came back down near where it started.

    /// How far an ankle may wander over `footPlantWindow` and still count as
    /// planted, in torso lengths. Wider than the tracker's jitter, narrower
    /// than any real movement.
    static let footPlantRadius = 0.12
    /// The span the wandering is measured over, either side of each frame.
    static let footPlantWindow = 0.15
    /// How long the foot has to stay planted before it counts as placed.
    static let footSettleSeconds = 0.15
    /// A hop longer than this, in torso lengths, went to a new hold.
    static let footAdjustDistance = 0.9
    /// And one that took longer than this was a considered move, not a fidget.
    static let footAdjustSeconds = 2.0

    static func footAdjustments(frames: [PoseFrame]) -> Int {
        footAdjustmentTimes(frames: frames).count
    }

    /// The moments a foot was repositioned, so a finding can point at one.
    ///
    /// Two things have to be told apart from a real reposition, and they pull in
    /// opposite directions. Tracker jitter is small and fast; a foot creeping
    /// along with the body as the climber moves is slow but goes a long way.
    /// Neither a speed test nor a radius test catches both. A speed test calls
    /// jitter movement, and a radius test calls creep a series of placements:
    /// the first version of this returned 41 on a thirteen second boulder, and
    /// the second returned 19.
    ///
    /// So a frame counts as planted only when the ankle stayed inside a small
    /// circle across a window either side of it. Jitter passes that, because it
    /// never leaves the circle. Creep fails it, because given a third of a
    /// second it always does. Runs of planted frames are placements, and two
    /// placements close together in both space and time are a foot put down
    /// twice.
    static func footAdjustmentTimes(frames: [PoseFrame]) -> [Double] {
        guard let torso = medianTorso(frames), torso > 0.01 else { return [] }
        var out: [Double] = []

        for ankle in [JointID.leftAnkle, JointID.rightAnkle] {
            // Time has to stay attached to the point. Compacting the series away
            // from its timestamps was the other half of the original bug.
            let series: [(t: Double, p: CGPoint)] = frames.compactMap {
                guard let p = $0.pt(ankle) else { return nil }
                return (t: $0.time, p: p)
            }
            guard series.count > 4 else { continue }

            var planted = [Bool](repeating: false, count: series.count)
            var lo = 0, hi = 0
            for i in series.indices {
                while lo < i && series[i].t - series[lo].t > Self.footPlantWindow { lo += 1 }
                while hi < series.count - 1 && series[hi + 1].t - series[i].t <= Self.footPlantWindow {
                    hi += 1
                }
                var worst = 0.0
                for k in lo...hi { worst = max(worst, distance(series[k].p, series[i].p)) }
                planted[i] = worst / torso <= Self.footPlantRadius
            }

            // Runs of planted frames, each long enough to be a placement.
            var placements: [(start: Double, end: Double, at: CGPoint)] = []
            var runStart: Int?
            for i in series.indices {
                if planted[i] {
                    if runStart == nil { runStart = i }
                } else if let from = runStart {
                    appendPlacement(series, from, i - 1, &placements)
                    runStart = nil
                }
            }
            if let from = runStart { appendPlacement(series, from, series.count - 1, &placements) }

            guard placements.count > 1 else { continue }
            for k in 1..<placements.count {
                let from = placements[k - 1], to = placements[k]
                let moved = distance(from.at, to.at) / torso
                let gap = to.start - from.end
                if moved < Self.footAdjustDistance && gap < Self.footAdjustSeconds {
                    out.append(to.start)
                }
            }
        }
        return out.sorted()
    }

    private static func appendPlacement(_ series: [(t: Double, p: CGPoint)],
                                        _ from: Int, _ to: Int,
                                        _ into: inout [(start: Double, end: Double, at: CGPoint)]) {
        guard to >= from else { return }
        let span = series[to].t - series[from].t
        guard span >= Self.footSettleSeconds else { return }
        // The middle of the run, so a placement is named by where the foot
        // actually sat rather than by where it happened to arrive.
        let mid = series[(from + to) / 2].p
        into.append((series[from].t, series[to].t, mid))
    }

    /// The body scale, taken once for the whole clip. A median rather than a
    /// mean so one badly tracked frame cannot set the ruler.
    /// Straight line start to finish, in torso lengths.
    static func netTravel(_ path: [CGPoint], frames: [PoseFrame]) -> Double {
        guard let a = path.first, let b = path.last,
              let torso = medianTorso(frames), torso > 0.01 else { return 0 }
        return distance(a, b) / torso
    }

    static func medianTorso(_ frames: [PoseFrame]) -> Double? {
        let lengths = frames.compactMap { torsoLength($0) }.sorted()
        guard !lengths.isEmpty else { return nil }
        return lengths[lengths.count / 2]
    }

    // MARK: - Helpers

    static func speedSeries(path: [CGPoint], times: [Double]) -> [Double] {
        guard path.count > 1, times.count == path.count else { return [] }
        var out: [Double] = [0]
        for i in 1..<path.count {
            let dt = max(times[i] - times[i - 1], 0.0005)
            out.append(distance(path[i], path[i - 1]) / dt)
        }
        return out
    }

    static func pathLength(_ p: [CGPoint]) -> Double {
        guard p.count > 1 else { return 0 }
        return (1..<p.count).reduce(0.0) { $0 + distance(p[$1], p[$1 - 1]) }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Interior angle at `vertex`, in degrees.
    static func angle(at vertex: CGPoint, from a: CGPoint, to b: CGPoint) -> Double {
        let v1x = Double(a.x - vertex.x), v1y = Double(a.y - vertex.y)
        let v2x = Double(b.x - vertex.x), v2y = Double(b.y - vertex.y)
        let dot = v1x * v2x + v1y * v2y
        let m1 = (v1x * v1x + v1y * v1y).squareRoot()
        let m2 = (v2x * v2x + v2y * v2y).squareRoot()
        guard m1 > 0, m2 > 0 else { return 180 }
        let cosine: Double = max(-1.0, min(1.0, dot / (m1 * m2)))
        return Foundation.acos(cosine) * 180 / Double.pi
    }
}
