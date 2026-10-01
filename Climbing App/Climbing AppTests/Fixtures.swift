import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Synthetic climbers, built so every expected value is known from the geometry
/// rather than from a previous run of the code.
enum Fixture {

    static func joint(_ x: Double, _ y: Double, _ c: Double = 0.9) -> Joint {
        Joint(x: x, y: y, confidence: c)
    }

    /// A body whose torso is exactly 0.20 tall, so center-of-mass offsets read
    /// directly in torso lengths.
    static func body(t: Double, comY: Double, feetX: Double,
                     wrist: CGPoint, hipX: Double? = nil) -> PoseFrame {
        let hx = hipX ?? feetX
        let joints: [JointID: Joint] = [
            .leftShoulder: joint(hx - 0.04, comY - 0.20),
            .rightShoulder: joint(hx + 0.04, comY - 0.20),
            .leftElbow: joint(hx - 0.08, comY - 0.12),
            .rightElbow: joint(hx + 0.08, comY - 0.12),
            .leftWrist: joint(wrist.x, wrist.y),
            .rightWrist: joint(wrist.x, wrist.y),
            .leftHip: joint(hx - 0.03, comY),
            .rightHip: joint(hx + 0.03, comY),
            .leftKnee: joint(feetX - 0.03, comY + 0.10),
            .rightKnee: joint(feetX + 0.03, comY + 0.10),
            .leftAnkle: joint(feetX - 0.02, comY + 0.19),
            .rightAnkle: joint(feetX + 0.02, comY + 0.19)
        ]
        return PoseFrame(time: t, joints: joints,
                         com: CGPoint(x: hx, y: comY), meanConfidence: 0.9)
    }

    /// Arms held still, either bent to a right angle or hanging straight.
    static func arms(bent: Bool, count: Int = 60) -> ([PoseFrame], [Double]) {
        var frames: [PoseFrame] = []
        var times: [Double] = []
        for i in 0..<count {
            let t = Double(i) / 30
            // Wrist directly above the elbow. Shoulder beside it gives 90 degrees,
            // shoulder below it gives 180.
            let shoulder = bent ? CGPoint(x: 0.60, y: 0.50) : CGPoint(x: 0.50, y: 0.60)
            let joints: [JointID: Joint] = [
                .leftShoulder: joint(shoulder.x, shoulder.y),
                .rightShoulder: joint(shoulder.x, shoulder.y),
                .leftElbow: joint(0.50, 0.50), .rightElbow: joint(0.50, 0.50),
                .leftWrist: joint(0.50, 0.40), .rightWrist: joint(0.50, 0.40)
            ]
            frames.append(PoseFrame(time: t, joints: joints,
                                    com: CGPoint(x: 0.5, y: 0.5), meanConfidence: 0.9))
            times.append(t)
        }
        return (frames, times)
    }

    /// A climber going straight up the wall with a full skeleton.
    static func straightAscent(count: Int = 90) -> [PoseFrame] {
        (0..<count).map { i in
            let y = 0.9 - Double(i) * 0.007
            let joints: [JointID: Joint] = [
                .leftShoulder: joint(0.46, y - 0.10), .rightShoulder: joint(0.54, y - 0.10),
                .leftElbow: joint(0.42, y - 0.05), .rightElbow: joint(0.58, y - 0.05),
                .leftWrist: joint(0.44, y - 0.16), .rightWrist: joint(0.56, y - 0.16),
                .leftHip: joint(0.47, y), .rightHip: joint(0.53, y),
                .leftKnee: joint(0.45, y + 0.10), .rightKnee: joint(0.55, y + 0.10),
                .leftAnkle: joint(0.44, y + 0.19), .rightAnkle: joint(0.56, y + 0.19)
            ]
            return PoseFrame(time: Double(i) / 30, joints: joints,
                             com: CenterOfMass.estimate(joints: joints), meanConfidence: 0.9)
        }
    }

    // MARK: Paths

    static func straightPath(_ n: Int = 20) -> [CGPoint] {
        (0..<n).map { CGPoint(x: 0.5, y: 0.9 - Double($0) * 0.04) }
    }

    static func circlePath(_ n: Int = 120, r: Double = 0.3) -> [CGPoint] {
        (0..<n).map {
            let a = Double($0) / Double(n) * 2 * .pi
            return CGPoint(x: 0.5 + r * cos(a), y: 0.5 + r * sin(a))
        }
    }

    /// An S-shaped line up the wall. One plausible sequence.
    static func sPath(amplitude: Double = 0.18, n: Int = 60) -> [CGPoint] {
        (0..<n).map {
            let t = Double($0) / Double(n - 1)
            return CGPoint(x: 0.5 + amplitude * sin(t * 2 * .pi), y: 0.9 - t * 0.7)
        }
    }

    // MARK: Records

    static func metrics(path: [CGPoint] = straightPath(),
                        entropy: Double = 1.0, elbow: Double = 180,
                        jerk: Double = 5, ratio: Double = 1.2, feet: Int = 0,
                        offset: Double = 0, deadpoints: [Double] = [],
                        confidence: Double = 0.9,
                        moveWaste: Double? = nil,
                        movingJerk: Double? = nil,
                        dynamicShare: Double? = nil,
                        reachTorsos: Double? = nil) -> Metrics {
        Metrics(entropy: entropy, logJerk: jerk, pathRatio: ratio,
                staticElbowAngle: elbow, pauseCount: 0, pauseTotal: 0,
                footAdjustments: feet, comOffsetFromFeet: offset,
                deadpointOffsets: deadpoints, comPath: path,
                duration: 20, trackingConfidence: confidence,
                moveWaste: moveWaste,
                // Smoothness is judged per move now, so a fixture that wants to
                // be judged on it has to carry the per-move number. Defaulting
                // it to the whole-climb one would put the two back in the same
                // pot, which is the thing that went wrong.
                movingJerk: movingJerk,
                dynamicShare: dynamicShare, reachTorsos: reachTorsos)
    }

    static func climb(path: [CGPoint], entropy: Double, kind: LeakKind? = nil,
                      elbow: Double = 180, daysAgo: Double = 0,
                      confidence: Double = 0.9, label: String = "test") -> Climb {
        let findings = kind.map {
            [Finding(kind: $0, severity: .costly, start: 0, end: 1, message: "x")]
        } ?? []
        return Climb(recordedAt: Date().addingTimeInterval(-daysAgo * 86400),
                     videoFilename: "x.mov", label: label,
                     metrics: metrics(path: path, entropy: entropy, elbow: elbow,
                                      confidence: confidence),
                     findings: findings, frames: [])
    }
}
