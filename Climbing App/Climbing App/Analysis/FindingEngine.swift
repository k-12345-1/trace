import Foundation

/// Turns metrics into findings, ranked by what they cost.
///
/// Two rules are enforced here rather than left to the copywriting:
///   1. Never name a hold or prescribe a sequence.
///   2. Say nothing when tracking was poor.
enum FindingEngine {

    static func findings(from m: Metrics, frames: [PoseFrame]) -> [Finding] {
        guard m.isTrustworthy else { return [] }
        var out: [Finding] = []

        // Bent arms while static. The most expensive common leak.
        if m.staticElbowAngle < 155 {
            let severity: Severity = m.staticElbowAngle < 115 ? .dominant
                                   : m.staticElbowAngle < 130 ? .costly
                                   : m.staticElbowAngle < 145 ? .moderate : .minor
            let worst = worstStaticElbowWindow(frames: frames)
            out.append(Finding(
                kind: .bentArms,
                severity: severity,
                start: worst?.start ?? 0,
                end: worst?.end ?? 0,
                message: "You held your arms at about \(Int(m.staticElbowAngle.rounded())) degrees while you were not moving. Straight arms would hand that load to your skeleton instead of your biceps."
            ))
        }

        // Weight hanging off the arms rather than sitting over the feet.
        if m.comOffsetFromFeet > 0.35 {
            let severity: Severity = m.comOffsetFromFeet > 0.90 ? .dominant
                                   : m.comOffsetFromFeet > 0.70 ? .costly
                                   : m.comOffsetFromFeet > 0.50 ? .moderate : .minor
            let percent = Int((m.comOffsetFromFeet * 100).rounded())
            out.append(Finding(
                kind: .weightOnArms,
                severity: severity,
                start: 0, end: m.duration,
                message: "While you were resting, your centre of mass sat about \(percent) percent of a torso length out from over your feet. That load is going through your fingers instead of your legs."
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
            out.append(Finding(
                kind: .mistimedDynamics,
                severity: severity,
                start: 0, end: m.duration,
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
            out.append(Finding(
                kind: .wandering,
                severity: severity,
                start: 0, end: m.duration,
                message: "Your hips travelled \(extra) percent further than the straight line up this climb. Some of that is the sequence, and some of it is drift you can take out on the next go."
            ))
        }

        // Start-stop movement.
        if m.logJerk > 8.5 {
            let severity: Severity = m.logJerk > 12 ? .costly : m.logJerk > 10 ? .moderate : .minor
            out.append(Finding(
                kind: .lurchy,
                severity: severity,
                start: 0, end: m.duration,
                message: "Your movement was lurchy rather than continuous. Every acceleration and deceleration is paid for by your forearms."
            ))
        }

        // Hesitation.
        if m.pauseTotal > m.duration * 0.35 && m.pauseCount >= 2 {
            let severity: Severity = m.pauseTotal > m.duration * 0.6 ? .costly : .moderate
            out.append(Finding(
                kind: .hesitation,
                severity: severity,
                start: 0, end: m.duration,
                message: "You spent \(Int(m.pauseTotal.rounded())) of \(Int(m.duration.rounded())) seconds not moving, across \(m.pauseCount) stops. That is route reading done while hanging on the wall rather than from the ground."
            ))
        }

        // Foot precision.
        if m.footAdjustments >= 3 {
            let severity: Severity = m.footAdjustments >= 8 ? .costly
                                   : m.footAdjustments >= 5 ? .moderate : .minor
            out.append(Finding(
                kind: .impreciseFeet,
                severity: severity,
                start: 0, end: m.duration,
                message: "You repositioned a foot after placing it \(m.footAdjustments) times. Placing once means looking at the foot until it lands."
            ))
        }

        return out.sorted { $0.severity > $1.severity }
    }

    /// The longest still stretch with the most bent arms, so the headline finding
    /// can point at a real moment in the video.
    private static func worstStaticElbowWindow(frames: [PoseFrame]) -> (start: Double, end: Double)? {
        let times = frames.map { $0.time }
        let path = frames.compactMap { $0.com }
        guard path.count == times.count else { return nil }

        let stops = MetricsEngine.pauses(path: path, times: times)
        var best: (start: Double, end: Double, angle: Double)?

        for stop in stops {
            let inWindow = frames.filter { $0.time >= stop.start && $0.time <= stop.end }
            var angles: [Double] = []
            for f in inWindow {
                for side in [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                             (JointID.rightShoulder, JointID.rightElbow, JointID.rightWrist)] {
                    guard let s = f.pt(side.0), let e = f.pt(side.1), let w = f.pt(side.2)
                    else { continue }
                    angles.append(MetricsEngine.angle(at: e, from: s, to: w))
                }
            }
            guard !angles.isEmpty else { continue }
            let mean = angles.reduce(0, +) / Double(angles.count)
            if best == nil || mean < best!.angle {
                best = (stop.start, stop.end, mean)
            }
        }
        guard let best else { return nil }
        return (best.start, best.end)
    }
}
