import Foundation
import CoreGraphics

/// Everything in here is arithmetic on a joint time series. No machine learning
/// beyond the pose model itself.
///
/// All of it is beta-agnostic by construction: nothing reads the wall, the holds,
/// or the sequence. It measures how well you executed whatever you chose to do.
enum MetricsEngine {

    /// COM speed below this (normalised units per second) counts as "still".
    private static let stillSpeed = 0.035
    /// A still stretch longer than this is a pause worth mentioning.
    private static let pauseSeconds = 0.8
    /// Wrist speed above this counts as a hand being thrown rather than adjusted.
    private static let reachSpeed = 0.25
    /// A hand has to travel this far to count as having gone to a new hold.
    private static let reachDistance = 0.05
    /// A hand contact further than this from any apex was not a dynamic move.
    private static let deadpointWindow = 0.6

    static func compute(frames: [PoseFrame]) -> Metrics {
        let tracked = frames.filter { $0.meanConfidence > 0 && $0.com != nil }
        let confidence = frames.isEmpty ? 0 : Double(tracked.count) / Double(frames.count)
        let duration = (frames.last?.time ?? 0) - (frames.first?.time ?? 0)

        let path = tracked.compactMap { $0.com }
        let times = tracked.map { $0.time }

        let length = pathLength(path)
        let straight = (path.first != nil && path.last != nil)
            ? distance(path.first!, path.last!) : 0
        let stops = pauses(path: path, times: times)

        return Metrics(
            entropy: geometricEntropy(path: path, length: length),
            logJerk: logDimensionlessJerk(path: path, times: times, length: length),
            pathRatio: straight > 0.001 ? length / straight : 0,
            staticElbowAngle: staticElbow(frames: tracked, times: times),
            pauseCount: stops.count,
            pauseTotal: stops.reduce(0) { $0 + ($1.end - $1.start) },
            footAdjustments: footAdjustments(frames: tracked),
            comOffsetFromFeet: comOffsetFromFeet(frames: tracked, times: times),
            deadpointOffsets: deadpointOffsets(frames: tracked, times: times),
            comPath: path,
            duration: duration,
            trackingConfidence: confidence
        )
    }

    // MARK: - Weight on arms rather than feet
    //
    // How far the centre of mass sits sideways of the feet, in torso lengths, while
    // the climber is not moving. Normalising by torso length is what makes it
    // independent of how far away the phone was.
    //
    // Note this is a projection, so it means different things at different camera
    // angles. Filmed side on, which is what Spotter asks for, it reads as hips
    // hanging away from the wall. Filmed front on it reads as a barn door.

    static func comOffsetFromFeet(frames: [PoseFrame], times: [Double]) -> Double {
        let path = frames.compactMap { $0.com }
        let speeds = speedSeries(path: path, times: times)
        var samples: [Double] = []

        for (i, frame) in frames.enumerated() {
            guard i < speeds.count, speeds[i] < stillSpeed,
                  let com = frame.com,
                  let base = baseOfSupport(frame),
                  let torso = torsoLength(frame), torso > 0.02 else { continue }
            samples.append(abs(Double(com.x) - base) / torso)
        }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

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

    /// Moments where the centre of mass stopped rising. In image coordinates y grows
    /// downward, so rising means a negative vertical velocity.
    static func verticalApexes(path: [CGPoint], times: [Double]) -> [Double] {
        guard path.count > 2, times.count == path.count else { return [] }
        var out: [Double] = []
        var previous = 0.0

        for i in 1..<path.count {
            let dt = max(times[i] - times[i - 1], 0.0005)
            let vy = Double(path[i].y - path[i - 1].y) / dt
            if previous < -0.01 && vy >= -0.01 { out.append(times[i]) }
            previous = vy
        }
        return out
    }

    /// Times at which a hand was thrown somewhere new and then settled.
    static func handContacts(frames: [PoseFrame], times: [Double], joint: JointID) -> [Double] {
        var out: [Double] = []
        var moving = false
        var launchedFrom: CGPoint?
        var previous: CGPoint?
        var previousTime = times.first ?? 0

        for (i, frame) in frames.enumerated() {
            guard i < times.count, let p = frame.pt(joint) else {
                previous = nil
                continue
            }
            let t = times[i]
            defer { previous = p; previousTime = t }

            guard let last = previous else { continue }
            let dt = max(t - previousTime, 0.0005)
            let speed = distance(p, last) / dt

            if speed > reachSpeed {
                if !moving {
                    moving = true
                    launchedFrom = last
                }
            } else if moving {
                moving = false
                if let origin = launchedFrom, distance(p, origin) > reachDistance {
                    out.append(t)
                }
                launchedFrom = nil
            }
        }
        return out
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
    // Log dimensionless jerk. Third derivative of COM position, normalised by
    // duration and path length so clips of different lengths compare. Lower is
    // smoother. Comparable within one capture setup, not across setups.

    static func logDimensionlessJerk(path: [CGPoint], times: [Double], length: Double) -> Double {
        guard path.count > 6, length > 0.001 else { return 0 }
        let dt = (times.last! - times.first!) / Double(times.count - 1)
        guard dt > 0.0005 else { return 0 }

        func derive(_ series: [CGPoint]) -> [CGPoint] {
            guard series.count > 1 else { return [] }
            return (1..<series.count).map {
                CGPoint(x: (series[$0].x - series[$0 - 1].x) / dt,
                        y: (series[$0].y - series[$0 - 1].y) / dt)
            }
        }
        let jerk = derive(derive(derive(path)))
        guard !jerk.isEmpty else { return 0 }

        let integral = jerk.reduce(0.0) { $0 + ($1.x * $1.x + $1.y * $1.y) * dt }
        let T = times.last! - times.first!
        guard T > 0, integral > 0 else { return 0 }

        let dimensionless = pow(T, 5) / (length * length) * integral
        return log(max(dimensionless, 1e-9))
    }

    // MARK: - Bent arms while static
    //
    // The most common and most expensive leak. Biceps holding a load the skeleton
    // would hold for free. Only counted while the COM is near-still, because a bent
    // arm mid-pull is just pulling.

    static func staticElbow(frames: [PoseFrame], times: [Double]) -> Double {
        let speeds = speedSeries(path: frames.compactMap { $0.com }, times: times)
        var angles: [Double] = []

        for (i, frame) in frames.enumerated() {
            guard i < speeds.count, speeds[i] < stillSpeed else { continue }
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

    static func pauses(path: [CGPoint], times: [Double]) -> [Pause] {
        let speeds = speedSeries(path: path, times: times)
        var out: [Pause] = []
        var runStart: Double?

        for (i, s) in speeds.enumerated() {
            let t = i < times.count ? times[i] : 0
            if s < stillSpeed {
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
    // A foot that lands, shifts, and lands again. High counts mean you are not
    // looking at your feet.

    static func footAdjustments(frames: [PoseFrame]) -> Int {
        var count = 0
        for ankle in [JointID.leftAnkle, JointID.rightAnkle] {
            let series = frames.compactMap { $0.pt(ankle) }
            guard series.count > 8 else { continue }

            var moving = false
            var sinceSettle = 0
            for i in 1..<series.count {
                let d = distance(series[i], series[i - 1])
                if d > 0.006 {
                    if !moving { moving = true }
                } else if moving {
                    moving = false
                    // A settle that lands soon after the previous one is a correction,
                    // not a fresh placement. Roughly 1.5s at 30fps.
                    if sinceSettle > 0 && sinceSettle < 45 { count += 1 }
                    sinceSettle = 0
                } else {
                    sinceSettle += 1
                }
            }
        }
        return count
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
