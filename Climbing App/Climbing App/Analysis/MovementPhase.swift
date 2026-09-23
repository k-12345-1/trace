import Foundation
import CoreGraphics

/// What the climber is doing, frame by frame.
///
/// The overlay used to draw a skeleton and say nothing. This names the state, the
/// way PlayVision labels a basketball player as planting a foot: a running
/// commentary rather than a diagram.
///
/// Nothing new is measured here. Every phase falls out of numbers MetricsEngine
/// already computes, which is why it costs no extra passes over the video.
enum MovementPhase: String, Codable, CaseIterable {
    case resting        // still long enough that it is a rest, not a pause
    case still          // momentarily stopped
    case reaching       // a hand travelling to a new hold
    case deadpoint      // at the top of the arc, weightless
    case footSet        // a foot being placed
    case moving         // continuous movement, nothing else notable

    var label: String {
        switch self {
        case .resting:   return "Resting"
        case .still:     return "Still"
        case .reaching:  return "Reaching"
        case .deadpoint: return "Deadpoint"
        case .footSet:   return "Foot set"
        case .moving:    return "Moving"
        }
    }

    /// Only the phases that cost something are highlighted. Moving is the
    /// baseline and should not shout.
    var isNotable: Bool {
        self == .deadpoint || self == .resting || self == .footSet
    }
}

enum PhaseTimeline {

    /// Speeds below this count as stopped, matching MetricsEngine.
    private static let stillSpeed = 0.035
    private static let restSeconds = 0.8
    private static let reachSpeed = 0.25
    private static let deadpointWindow = 0.18

    /// One phase per tracked frame, in the same order the frames come in.
    static func build(frames: [PoseFrame]) -> [MovementPhase] {
        guard !frames.isEmpty else { return [] }
        let times = frames.map { $0.time }
        let path = frames.map { $0.com }

        let comSpeeds = speeds(of: path, times: times)
        let leftWrist = speeds(of: frames.map { $0.pt(.leftWrist) }, times: times)
        let rightWrist = speeds(of: frames.map { $0.pt(.rightWrist) }, times: times)
        let leftAnkle = speeds(of: frames.map { $0.pt(.leftAnkle) }, times: times)
        let rightAnkle = speeds(of: frames.map { $0.pt(.rightAnkle) }, times: times)

        let apexes = MetricsEngine.verticalApexes(
            path: frames.compactMap { $0.com },
            times: frames.filter { $0.com != nil }.map { $0.time })

        // A stretch of stillness only becomes a rest once it has lasted.
        var restUntil = -1.0
        var runStart: Double?
        for (i, s) in comSpeeds.enumerated() {
            let t = times[i]
            if s < stillSpeed {
                if runStart == nil { runStart = t }
                if let start = runStart, t - start >= restSeconds { restUntil = max(restUntil, t) }
            } else {
                runStart = nil
            }
        }

        var out: [MovementPhase] = []
        for i in frames.indices {
            let t = times[i]
            let com = comSpeeds[i]

            // Ranked: the rarest and most expensive state wins the label.
            if apexes.contains(where: { abs($0 - t) <= deadpointWindow }) {
                out.append(.deadpoint)
            } else if max(leftWrist[i], rightWrist[i]) > reachSpeed {
                out.append(.reaching)
            } else if max(leftAnkle[i], rightAnkle[i]) > reachSpeed * 0.55 {
                out.append(.footSet)
            } else if com < stillSpeed {
                out.append(isResting(at: t, comSpeeds: comSpeeds, times: times) ? .resting : .still)
            } else {
                out.append(.moving)
            }
        }
        return out
    }

    /// True when the stillness around this instant lasts long enough to be a rest.
    private static func isResting(at t: Double, comSpeeds: [Double], times: [Double]) -> Bool {
        var start = t, end = t
        if let i = times.firstIndex(of: t) {
            var j = i
            while j > 0, comSpeeds[j - 1] < stillSpeed { j -= 1; start = times[j] }
            var k = i
            while k < comSpeeds.count - 1, comSpeeds[k + 1] < stillSpeed { k += 1; end = times[k] }
        }
        return end - start >= restSeconds
    }

    private static func speeds(of points: [CGPoint?], times: [Double]) -> [Double] {
        guard points.count == times.count, points.count > 1 else {
            return Array(repeating: 0, count: max(points.count, 0))
        }
        var out: [Double] = [0]
        for i in 1..<points.count {
            guard let a = points[i], let b = points[i - 1] else { out.append(0); continue }
            let dt = max(times[i] - times[i - 1], 0.0005)
            out.append(MetricsEngine.distance(a, b) / dt)
        }
        return out
    }

    // MARK: Live readout
    //
    // Speeds are reported in body lengths per second. A phone cannot know how far
    // away the climber is, so metres would be invented; body lengths are real and
    // survive the camera being moved.

    struct Readout {
        var phase: MovementPhase
        var speed: Double          // body lengths per second
        /// The same speed before any normalising, in image units per second.
        /// This is what BodyScale needs to say it in metres.
        var speedRaw: Double
        var elbow: Double?         // degrees, when both arms are visible
        var box: CGRect            // the tracked climber, normalised
    }

    static func readout(frames: [PoseFrame], phases: [MovementPhase], at time: Double) -> Readout? {
        guard !frames.isEmpty, frames.count == phases.count else { return nil }
        var index = 0
        var best = Double.greatestFiniteMagnitude
        for (i, f) in frames.enumerated() where abs(f.time - time) < best {
            best = abs(f.time - time); index = i
        }
        let frame = frames[index]
        guard let box = boundingBox(frame) else { return nil }

        // Body length as the scale reference, so the number means the same thing
        // whether the phone was two metres away or five.
        let body = max(box.height, 0.05)
        var raw = 0.0
        if index > 0, let a = frame.com, let b = frames[index - 1].com {
            let dt = max(frame.time - frames[index - 1].time, 0.0005)
            raw = MetricsEngine.distance(a, b) / dt
        }
        let speed = raw / body

        var elbow: Double?
        var angles: [Double] = []
        for side in [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                     (JointID.rightShoulder, JointID.rightElbow, JointID.rightWrist)] {
            guard let s = frame.pt(side.0), let e = frame.pt(side.1), let w = frame.pt(side.2)
            else { continue }
            angles.append(MetricsEngine.angle(at: e, from: s, to: w))
        }
        if !angles.isEmpty { elbow = angles.reduce(0, +) / Double(angles.count) }

        return Readout(phase: phases[index], speed: speed, speedRaw: raw,
                       elbow: elbow, box: box)
    }

    /// The tracked subject, from the spread of their own joints.
    static func boundingBox(_ frame: PoseFrame) -> CGRect? {
        let points = JointID.allCases.compactMap { frame.pt($0) }
        guard points.count >= 5 else { return nil }
        let xs = points.map { Double($0.x) }, ys = points.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let padX = (maxX - minX) * 0.14, padY = (maxY - minY) * 0.07
        return CGRect(x: minX - padX, y: minY - padY,
                      width: (maxX - minX) + padX * 2,
                      height: (maxY - minY) + padY * 2)
    }
}
