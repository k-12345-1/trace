import Foundation

/// Turns metrics into findings, ranked by what they cost.
///
/// Three rules are enforced here rather than left to the copywriting:
///   1. Never name a hold or prescribe a sequence.
///   2. Say nothing when tracking was poor.
///   3. Every finding points at a moment. A finding timed at 0:00 that actually
///      means "somewhere in this clip" is a finding you cannot check, and one
///      you cannot check is one you have to take on faith.
enum FindingEngine {

    /// - Parameter priorJerk: log dimensionless jerk from this climber's own
    ///   earlier tracked attempts. Smoothness has no defensible absolute scale,
    ///   so it is judged against their own history or not at all.
    static func findings(from m: Metrics, frames: [PoseFrame],
                         priorJerk: [Double] = []) -> [Finding] {
        guard m.isTrustworthy else { return [] }
        var out: [Finding] = []
        let whole = (start: 0.0, end: m.duration)

        // Bent arms while static. The most expensive common leak.
        if m.staticElbowAngle < 155 {
            let severity: Severity = m.staticElbowAngle < 115 ? .dominant
                                   : m.staticElbowAngle < 130 ? .costly
                                   : m.staticElbowAngle < 145 ? .moderate : .minor
            let worst = worstStaticElbowWindow(frames: frames) ?? whole
            out.append(Finding(
                kind: .bentArms,
                severity: severity,
                start: worst.start,
                end: worst.end,
                message: "You held your arms at about \(Int(m.staticElbowAngle.rounded())) degrees while you were not moving. Straight arms would hand that load to your skeleton instead of your biceps."
            ))
        }

        // Weight hanging off the arms rather than sitting over the feet.
        if m.comOffsetFromFeet > 0.35 {
            let severity: Severity = m.comOffsetFromFeet > 0.90 ? .dominant
                                   : m.comOffsetFromFeet > 0.70 ? .costly
                                   : m.comOffsetFromFeet > 0.50 ? .moderate : .minor
            let percent = Int((m.comOffsetFromFeet * 100).rounded())
            let w = worstOffsetWindow(frames: frames) ?? whole
            // "Resting" was wrong: the measurement is taken over every frame
            // where the centre of mass was barely moving, which on a climb with
            // no pauses in it is not a rest at all.
            out.append(Finding(
                kind: .weightOnArms,
                severity: severity,
                start: w.start, end: w.end,
                message: "Over the stretches where you were barely moving, your centre of mass sat about \(percent) percent of a torso length out from over your feet. That load is going through your fingers instead of your legs."
            ))
        }

        // Dynamic moves caught off the apex.
        if m.hasDynamicMoves && m.meanDeadpointError > 120 {
            let severity: Severity = m.meanDeadpointError > 320 ? .costly
                                   : m.meanDeadpointError > 200 ? .moderate : .minor
            let ms = Int(m.meanDeadpointError.rounded())
            let late = m.deadpointBias > 40
            let early = m.deadpointBias < -40
            let direction = late
                ? " You were mostly arriving late, catching on the way back down, which means pulling your own weight back up."
                : early
                    ? " You were mostly arriving early, still driving upward into the hold."
                    : ""
            let w = worstDeadpointWindow(frames: frames) ?? whole
            out.append(Finding(
                kind: .mistimedDynamics,
                severity: severity,
                start: w.start, end: w.end,
                message: "On dynamic moves your hand arrived about \(ms) milliseconds away from the top of your arc.\(direction)"
            ))
        }

        // Wandering line. Path ratio is the most intuitive version of entropy.
        //
        // Zero means MetricsEngine declined to compute it, because the climb ended
        // near where it started. On a traverse or a circuit the straight line is
        // meaningless and so is anything divided by it.
        if m.pathRatio > 1.35 {
            let severity: Severity = m.pathRatio > 2.2 ? .costly
                                   : m.pathRatio > 1.7 ? .moderate : .minor
            let extra = Int(((m.pathRatio - 1) * 100).rounded())
            let w = worstDriftWindow(frames: frames) ?? whole
            out.append(Finding(
                kind: .wandering,
                severity: severity,
                start: w.start, end: w.end,
                message: "Your hips travelled \(extra) percent further than the straight line up this climb. Some of that is the sequence, and some of it is drift you can take out on the next go."
            ))
        }

        // Start-stop movement.
        //
        // Judged against this climber's own earlier attempts, never against a
        // number. Log dimensionless jerk is dominated by the pose tracker's noise
        // floor rather than by the climber, so the fixed thresholds this used to
        // carry were calibrated on synthetic fixtures and fired on every real
        // clip. A climber with no history yet gets no finding here, which is the
        // correct answer: you cannot call someone's movement lurchy before you
        // know what their normal looks like.
        if let excess = jerkExcess(m.logJerk, over: priorJerk) {
            let severity: Severity = excess > 1.5 ? .costly : excess > 0.9 ? .moderate : .minor
            let w = worstJerkWindow(frames: frames) ?? whole
            out.append(Finding(
                kind: .lurchy,
                severity: severity,
                start: w.start, end: w.end,
                message: "This attempt was more start-stop than your usual on this kind of climb. Every acceleration and deceleration is paid for by your forearms."
            ))
        }

        // Hesitation.
        if m.pauseTotal > m.duration * 0.35 && m.pauseCount >= 2 {
            let severity: Severity = m.pauseTotal > m.duration * 0.6 ? .costly : .moderate
            let w = longestPauseWindow(frames: frames) ?? whole
            out.append(Finding(
                kind: .hesitation,
                severity: severity,
                start: w.start, end: w.end,
                message: "You spent \(Int(m.pauseTotal.rounded())) of \(Int(m.duration.rounded())) seconds not moving, across \(m.pauseCount) stops. That is route reading done while hanging on the wall rather than from the ground."
            ))
        }

        // Foot precision.
        if m.footAdjustments >= 3 {
            let severity: Severity = m.footAdjustments >= 8 ? .costly
                                   : m.footAdjustments >= 5 ? .moderate : .minor
            let w = busiestFootWindow(frames: frames) ?? whole
            out.append(Finding(
                kind: .impreciseFeet,
                severity: severity,
                start: w.start, end: w.end,
                message: "You repositioned a foot after placing it \(m.footAdjustments) times. Placing once means looking at the foot until it lands."
            ))
        }

        return out.sorted { $0.severity > $1.severity }
    }

    // MARK: - Pointing at a moment
    //
    // Every finding names a window. Most of them are found the same way: score
    // each frame, then take the best run of frames a second or so long. One
    // helper does that, and each finding supplies its own score.

    typealias Window = (start: Double, end: Double)

    /// How long a window is, in seconds. Long enough to watch, short enough to
    /// be about one thing.
    private static let windowSeconds = 1.2

    /// The run of frames with the highest total score. `score` returns nil for a
    /// frame that cannot be judged, and those frames never anchor a window.
    private static func bestWindow(frames: [PoseFrame],
                                   score: (PoseFrame) -> Double?) -> Window? {
        let scored: [(t: Double, v: Double)] = frames.compactMap {
            guard let v = score($0) else { return nil }
            return (t: $0.time, v: v)
        }
        guard scored.count >= 3 else { return nil }

        var best: (start: Double, end: Double, total: Double)?
        var j = 0, running = 0.0
        for i in 0..<scored.count {
            running += scored[i].v
            while scored[i].t - scored[j].t > Self.windowSeconds {
                running -= scored[j].v
                j += 1
            }
            if best == nil || running > best!.total {
                best = (scored[j].t, scored[i].t, running)
            }
        }
        guard let best, best.end > best.start else { return nil }
        return (best.start, best.end)
    }

    /// The stretch where the arms were most bent while the climber was barely
    /// moving. Scored per frame rather than per pause, because a climb with no
    /// pause in it still has a worst moment, and the old version returned
    /// nothing at all for one: which is how every finding ended up at 0:00.
    static func worstStaticElbowWindow(frames: [PoseFrame]) -> Window? {
        let times = frames.map { $0.time }
        let speeds = MetricsEngine.speedSeries(path: frames.compactMap { $0.com }, times: times)
        guard speeds.count == frames.count else { return nil }

        return bestWindow(frames: frames) { f in
            guard let i = frames.firstIndex(where: { $0.time == f.time }),
                  i < speeds.count, speeds[i] < 0.035 else { return nil }
            var angles: [Double] = []
            for side in [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                         (JointID.rightShoulder, JointID.rightElbow, JointID.rightWrist)] {
                guard let sh = f.pt(side.0), let e = f.pt(side.1), let w = f.pt(side.2)
                else { continue }
                angles.append(MetricsEngine.angle(at: e, from: sh, to: w))
            }
            guard !angles.isEmpty else { return nil }
            // A bent arm should score high, so the angle is inverted.
            return 180 - angles.reduce(0, +) / Double(angles.count)
        }
    }

    /// Where the centre of mass hung furthest out from over the feet.
    static func worstOffsetWindow(frames: [PoseFrame]) -> Window? {
        bestWindow(frames: frames) { f in
            guard let com = f.com,
                  let base = MetricsEngine.baseOfSupport(f),
                  let torso = MetricsEngine.torsoLength(f), torso > 0.02 else { return nil }
            return abs(Double(com.x) - base) / torso
        }
    }

    /// Where the movement was roughest, measured the same way the metric is:
    /// the magnitude of the third derivative of the centre-of-mass path.
    static func worstJerkWindow(frames: [PoseFrame]) -> Window? {
        let usable = frames.filter { $0.com != nil }
        guard usable.count > 8 else { return nil }
        let path = usable.compactMap { $0.com }
        let times = usable.map { $0.time }

        var magnitude = [Double](repeating: 0, count: usable.count)
        for i in 3..<usable.count {
            let dt = max((times[i] - times[i - 3]) / 3, 0.0005)
            // Third difference, which is jerk up to a constant factor.
            let x = Double(path[i].x - 3 * path[i - 1].x + 3 * path[i - 2].x - path[i - 3].x)
            let y = Double(path[i].y - 3 * path[i - 1].y + 3 * path[i - 2].y - path[i - 3].y)
            magnitude[i] = (x * x + y * y).squareRoot() / (dt * dt * dt)
        }

        var byTime: [Double: Double] = [:]
        for (i, f) in usable.enumerated() { byTime[f.time] = magnitude[i] }
        return bestWindow(frames: usable) { byTime[$0.time] }
    }

    /// Where the climber drifted furthest sideways of their own average line.
    static func worstDriftWindow(frames: [PoseFrame]) -> Window? {
        let xs = frames.compactMap { $0.com?.x }.map(Double.init)
        guard !xs.isEmpty else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        return bestWindow(frames: frames) { f in
            guard let com = f.com else { return nil }
            return abs(Double(com.x) - mean)
        }
    }

    /// The dynamic move caught furthest from the top of its arc.
    static func worstDeadpointWindow(frames: [PoseFrame]) -> Window? {
        let usable = frames.filter { $0.com != nil }
        guard usable.count > 2 else { return nil }
        let apexes = MetricsEngine.verticalApexes(path: usable.compactMap { $0.com },
                                                  times: usable.map { $0.time })
        guard let last = frames.last?.time else { return nil }
        // The apexes are the moments worth watching. The last one is as good a
        // pick as any without re-deriving which hand arrived when, and it is the
        // one still fresh in the climber's memory.
        guard let apex = apexes.last else { return nil }
        return (max(0, apex - 0.6), min(last, apex + 0.6))
    }

    /// The longest stretch of not moving.
    static func longestPauseWindow(frames: [PoseFrame]) -> Window? {
        let times = frames.map { $0.time }
        let path = frames.compactMap { $0.com }
        guard path.count == times.count else { return nil }
        let stops = MetricsEngine.pauses(path: path, times: times)
        guard let longest = stops.max(by: { ($0.end - $0.start) < ($1.end - $1.start) })
        else { return nil }
        return (longest.start, longest.end)
    }

    /// The second and a bit containing the most foot repositions.
    static func busiestFootWindow(frames: [PoseFrame]) -> Window? {
        let moments = MetricsEngine.footAdjustmentTimes(frames: frames)
        guard let first = moments.first else { return nil }
        guard moments.count > 1 else { return (max(0, first - 0.6), first + 0.6) }

        var best = (start: first, count: 0)
        for anchor in moments {
            let n = moments.filter { $0 >= anchor && $0 <= anchor + Self.windowSeconds }.count
            if n > best.count { best = (anchor, n) }
        }
        return (max(0, best.start - 0.3), best.start + Self.windowSeconds)
    }

    // MARK: - Smoothness, relative to yourself

    /// How much rougher this attempt was than this climber's own usual, in
    /// natural-log units, or nil when there is no usual yet or it was not worse.
    ///
    /// Three prior attempts is the minimum. Two give a median that is really
    /// just one of them, and a threshold set by a single earlier climb would be
    /// as arbitrary as the fixed one this replaced.
    static let minimumHistory = 3
    /// How far above the median counts as a real difference rather than spread.
    static let jerkMargin = 0.45

    static func jerkExcess(_ value: Double, over history: [Double]) -> Double? {
        let usable = history.filter { $0 != 0 }
        guard usable.count >= Self.minimumHistory else { return nil }
        let sorted = usable.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let excess = value - median
        return excess > Self.jerkMargin ? excess : nil
    }
}
