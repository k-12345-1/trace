import Testing
import Foundation
@testable import ClimbingApp

/// What counts as a foot step for the technique readings.
@Suite("Foot steps")
struct StepTests {
    /// The left foot, planted, then where you put it.
    private func frame(t: Double, leftAnkle: CGPoint) -> PoseFrame {
        let base = Fixture.body(t: t, comY: 0.5, feetX: 0.5, wrist: CGPoint(x: 0.5, y: 0.3))
        var joints = base.joints
        joints[.leftAnkle] = Fixture.joint(leftAnkle.x, leftAnkle.y)
        return PoseFrame(time: t, joints: joints, com: base.com, meanConfidence: 0.9)
    }

    /// A step of a torso counts; a leap of four torsos in a few frames is
    /// the tracker handing the ankle to the other leg, and does not.
    @Test func anImpossibleStepIsNotAStep() throws {
        let frames = (0..<150).map { i -> PoseFrame in
            let t = Double(i) / 30
            // Planted a second; a step of 0.2 up (a torso is about 0.2
            // here); planted a second; a leap of 0.8; planted a second.
            let y: Double = i < 30 ? 0.69 : i < 34 ? 0.69 - 0.05 * Double(i - 29) : i < 90 ? 0.49 : i < 94 ? 0.49 - 0.2 * Double(i - 89) : -0.31
            return frame(t: t, leftAnkle: CGPoint(x: 0.5, y: y))
        }
        let torso = try #require(MetricsEngine.medianTorso(frames))
        let steps = TechniqueEngine.steps(in: frames, torso: torso)
        let left = steps.filter { $0.ankle == .leftAnkle }
        #expect(left.count == 1, "\(left.map(\.time))")
        #expect(left.first.map { abs($0.time - 1.1) < 0.2 } == true)
    }
}
