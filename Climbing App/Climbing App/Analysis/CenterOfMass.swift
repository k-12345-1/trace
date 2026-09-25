import Foundation
import CoreGraphics

/// Center of mass from a 2D skeleton, using standard segment mass fractions
/// (Dempster). Accurate enough to compare one attempt against another, which is
/// all Trace ever does. It is never presented as an absolute figure.
enum CenterOfMass {

    /// Segment mass fractions, summing to 1.0.
    private struct Segment {
        let a: JointID, b: JointID, fraction: Double
    }

    private static let segments: [Segment] = [
        .init(a: .leftShoulder,  b: .rightShoulder, fraction: 0.081),  // head and neck, carried at the shoulders
        .init(a: .leftShoulder,  b: .rightHip,      fraction: 0.2485), // trunk, split across the diagonals
        .init(a: .rightShoulder, b: .leftHip,       fraction: 0.2485),
        .init(a: .leftShoulder,  b: .leftElbow,     fraction: 0.028),  // upper arms
        .init(a: .rightShoulder, b: .rightElbow,    fraction: 0.028),
        .init(a: .leftElbow,     b: .leftWrist,     fraction: 0.022),  // forearm and hand
        .init(a: .rightElbow,    b: .rightWrist,    fraction: 0.022),
        .init(a: .leftHip,       b: .leftKnee,      fraction: 0.100),  // thighs
        .init(a: .rightHip,      b: .rightKnee,     fraction: 0.100),
        .init(a: .leftKnee,      b: .leftAnkle,     fraction: 0.061),  // shank and foot
        .init(a: .rightKnee,     b: .rightAnkle,    fraction: 0.061)
    ]

    static func estimate(joints: [JointID: Joint]) -> CGPoint? {
        var x = 0.0, y = 0.0, weight = 0.0

        for s in segments {
            guard let a = joints[s.a], a.isUsable,
                  let b = joints[s.b], b.isUsable else { continue }
            x += (a.x + b.x) / 2 * s.fraction
            y += (a.y + b.y) / 2 * s.fraction
            weight += s.fraction
        }

        // Need most of the body present or the estimate drifts toward whatever limb
        // happened to track. Better to drop the frame.
        guard weight >= 0.6 else { return nil }
        return CGPoint(x: x / weight, y: y / weight)
    }
}
