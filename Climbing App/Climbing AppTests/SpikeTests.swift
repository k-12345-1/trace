import Testing
import Foundation
@testable import ClimbingApp

/// A one-frame tracker spike is repaired; a real move is left alone.
@Suite("Isolated joint spikes")
struct SpikeTests {
    private func frame(t: Double, ankleY: Double) -> PoseFrame {
        let base = Fixture.body(t: t, comY: 0.5, feetX: 0.5, wrist: CGPoint(x: 0.5, y: 0.3))
        var joints = base.joints
        joints[.leftAnkle] = Fixture.joint(0.5, ankleY)
        return PoseFrame(time: t, joints: joints, com: base.com, meanConfidence: 0.9)
    }

    @Test func aSpikeIsRepairedAndAStepIsKept() throws {
        // Planted, one frame flung a quarter of the frame away, planted;
        // later a genuine step up over four frames that stays up.
        var frames: [PoseFrame] = []
        for i in 0..<60 {
            let y: Double = i == 20 ? 0.45 : i < 40 ? 0.69 : i < 44 ? 0.69 - 0.05 * Double(i - 39) : 0.49
            frames.append(frame(t: Double(i) / 30, ankleY: y))
        }
        let fixed = PoseTracker.stabilizeIsolatedJoints(frames)
        let spiked = try #require(fixed[20].pt(.leftAnkle))
        #expect(abs(spiked.y - 0.69) < 0.01, "spike left at \(spiked.y)")
        let stepped = try #require(fixed[42].pt(.leftAnkle))
        #expect(abs(stepped.y - (0.69 - 0.15)) < 0.01, "the step was flattened to \(stepped.y)")
        #expect(fixed[50].pt(.leftAnkle)?.y == 0.49)
    }
}
