import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Friction, and the force pairs that make it.
///
/// Fixtures are built from geometry, so every expected answer is known without
/// running the code. `Fixture.body` has a torso of 0.20, so 0.20 in these
/// coordinates is one torso length.
@Suite("Force pairs")
struct ForceTests {

    /// A frame with the four contacts placed explicitly.
    private func frame(t: Double = 0, com: CGPoint,
                       leftHand: CGPoint, rightHand: CGPoint,
                       leftFoot: CGPoint, rightFoot: CGPoint) -> PoseFrame {
        let joints: [JointID: Joint] = [
            // Shoulders and hips 0.20 apart vertically, so the torso is 1.
            .leftShoulder: Fixture.joint(com.x - 0.04, com.y - 0.10),
            .rightShoulder: Fixture.joint(com.x + 0.04, com.y - 0.10),
            .leftHip: Fixture.joint(com.x - 0.03, com.y + 0.10),
            .rightHip: Fixture.joint(com.x + 0.03, com.y + 0.10),
            .leftWrist: Fixture.joint(leftHand.x, leftHand.y),
            .rightWrist: Fixture.joint(rightHand.x, rightHand.y),
            .leftAnkle: Fixture.joint(leftFoot.x, leftFoot.y),
            .rightAnkle: Fixture.joint(rightFoot.x, rightFoot.y)
        ]
        return PoseFrame(time: t, joints: joints, com: com, meanConfidence: 0.9)
    }

    // MARK: Bracketing

    @Test func hangingBetweenYourContactsIsBracketed() {
        let f = frame(com: CGPoint(x: 0.50, y: 0.50),
                      leftHand: CGPoint(x: 0.35, y: 0.30),
                      rightHand: CGPoint(x: 0.65, y: 0.30),
                      leftFoot: CGPoint(x: 0.40, y: 0.75),
                      rightFoot: CGPoint(x: 0.60, y: 0.75))
        #expect(ForceEngine.isBracketed(f) == true)
        #expect(ForceEngine.overhang(f) == 0)
    }

    @Test func hangingOutsideThemIsNot() {
        // Everything on the right, body swung out to the left.
        let f = frame(com: CGPoint(x: 0.20, y: 0.50),
                      leftHand: CGPoint(x: 0.60, y: 0.30),
                      rightHand: CGPoint(x: 0.70, y: 0.30),
                      leftFoot: CGPoint(x: 0.62, y: 0.75),
                      rightFoot: CGPoint(x: 0.68, y: 0.75))
        #expect(ForceEngine.isBracketed(f) == false)
        // 0.60 - 0.20 = 0.40, over a torso of 0.20, is two torso lengths.
        #expect(abs((ForceEngine.overhang(f) ?? 0) - 2.0) < 0.01)
    }

    @Test func aFrameWithNoContactsSaysNothing() {
        let bare = PoseFrame(time: 0, joints: [:], com: CGPoint(x: 0.5, y: 0.5),
                             meanConfidence: 0.9)
        #expect(ForceEngine.isBracketed(bare) == nil)
        #expect(ForceEngine.overhang(bare) == nil)
    }

    // MARK: Compression

    @Test func wideHandsWithTheBodyBetweenThemIsCompression() {
        // Hands 0.40 apart, which is two torso lengths, body in the middle.
        let f = frame(com: CGPoint(x: 0.50, y: 0.50),
                      leftHand: CGPoint(x: 0.30, y: 0.35),
                      rightHand: CGPoint(x: 0.70, y: 0.35),
                      leftFoot: CGPoint(x: 0.45, y: 0.75),
                      rightFoot: CGPoint(x: 0.55, y: 0.75))
        #expect(ForceEngine.isCompressing(f) == true)
    }

    @Test func twoHandsCloseTogetherIsNotCompression() {
        // Both on the same hold. There is no pair to oppose.
        let f = frame(com: CGPoint(x: 0.50, y: 0.50),
                      leftHand: CGPoint(x: 0.49, y: 0.35),
                      rightHand: CGPoint(x: 0.51, y: 0.35),
                      leftFoot: CGPoint(x: 0.45, y: 0.75),
                      rightFoot: CGPoint(x: 0.55, y: 0.75))
        #expect(ForceEngine.isCompressing(f) == false)
    }

    @Test func wideHandsWithTheBodyOutsideThemIsNotCompression() {
        let f = frame(com: CGPoint(x: 0.10, y: 0.50),
                      leftHand: CGPoint(x: 0.30, y: 0.35),
                      rightHand: CGPoint(x: 0.70, y: 0.35),
                      leftFoot: CGPoint(x: 0.30, y: 0.75),
                      rightFoot: CGPoint(x: 0.35, y: 0.75))
        #expect(ForceEngine.isCompressing(f) == false)
    }

    // MARK: Load angle

    @Test func hangingStraightDownIsZeroDegrees() {
        let angle = ForceEngine.loadAngle(from: CGPoint(x: 0.5, y: 0.3),
                                          to: CGPoint(x: 0.5, y: 0.6))
        #expect(abs(angle) < 0.01)
    }

    @Test func aSidepullReadsAsItsAngle() {
        // Equal across and down is forty five degrees, either way.
        let right = ForceEngine.loadAngle(from: CGPoint(x: 0.4, y: 0.3),
                                          to: CGPoint(x: 0.5, y: 0.4))
        let left = ForceEngine.loadAngle(from: CGPoint(x: 0.6, y: 0.3),
                                         to: CGPoint(x: 0.5, y: 0.4))
        #expect(abs(right - 45) < 0.01)
        #expect(abs(left - 45) < 0.01)
    }

    // MARK: f = μN, and what an angle costs

    /// The claim the results screen makes in words, checked as arithmetic.
    @Test func thirtyDegreesOffCostsThirteenPercent() {
        #expect(ForceEngine.frictionLost(offBy: 0) == 0)
        #expect(ForceEngine.frictionLost(offBy: 30) == 13)
        #expect(ForceEngine.frictionLost(offBy: 60) == 50)
        #expect(abs(ForceEngine.normalShare(offBy: 60) - 0.5) < 0.0001)
    }

    // MARK: Swings

    /// A dynamic move passes through an unbracketed instant. None of those is a
    /// fault, and a detector that counted them would fire on every climb.
    @Test func amomentPassingThroughIsNotASwing() {
        var frames: [PoseFrame] = []
        for i in 0..<60 {
            let t = Double(i) / 30
            // Out of the span for a fifth of a second, back in after.
            let x = (14...20).contains(i) ? 0.20 : 0.50
            frames.append(frame(t: t, com: CGPoint(x: x, y: 0.50),
                                leftHand: CGPoint(x: 0.40, y: 0.30),
                                rightHand: CGPoint(x: 0.60, y: 0.30),
                                leftFoot: CGPoint(x: 0.45, y: 0.75),
                                rightFoot: CGPoint(x: 0.55, y: 0.75)))
        }
        #expect(ForceEngine.swings(frames: frames).isEmpty)
        #expect(ForceEngine.swingTotal(frames: frames) == 0)
    }

    @Test func hangingOutThereIsASwing() {
        var frames: [PoseFrame] = []
        for i in 0..<90 {
            let t = Double(i) / 30
            let x = (20..<70).contains(i) ? 0.20 : 0.50   // a second and two thirds
            frames.append(frame(t: t, com: CGPoint(x: x, y: 0.50),
                                leftHand: CGPoint(x: 0.40, y: 0.30),
                                rightHand: CGPoint(x: 0.60, y: 0.30),
                                leftFoot: CGPoint(x: 0.45, y: 0.75),
                                rightFoot: CGPoint(x: 0.55, y: 0.75)))
        }
        let swings = ForceEngine.swings(frames: frames)
        #expect(swings.count == 1)
        #expect(abs((swings.first?.duration ?? 0) - 1.633) < 0.05)
        // 0.40 - 0.20 over a torso of 0.20 is one torso length.
        #expect(abs((swings.first?.peak ?? 0) - 1.0) < 0.01)
    }

    @Test func aClimbSpentInOppositionReadsAsOne() {
        let frames = (0..<60).map { i in
            frame(t: Double(i) / 30, com: CGPoint(x: 0.50, y: 0.50),
                  leftHand: CGPoint(x: 0.40, y: 0.30),
                  rightHand: CGPoint(x: 0.60, y: 0.30),
                  leftFoot: CGPoint(x: 0.45, y: 0.75),
                  rightFoot: CGPoint(x: 0.55, y: 0.75))
        }
        #expect(ForceEngine.bracketedFraction(frames: frames) == 1.0)
        #expect(ForceEngine.swingTotal(frames: frames) == 0)
    }

    // MARK: The finding

    @Test func swingingLongEnoughIsReported() {
        let m = Fixture.metrics()
        var swingy = m
        swingy.swingTotal = 5.0
        let findings = FindingEngine.findings(from: swingy, frames: [], priorJerk: [])
        let leak = findings.first { $0.kind == .unopposed }
        #expect(leak != nil)
        #expect(leak?.severity == .costly)
    }

    @Test func aSecondOfItIsNot() {
        var brief = Fixture.metrics()
        brief.swingTotal = 0.8
        let findings = FindingEngine.findings(from: brief, frames: [], priorJerk: [])
        #expect(!findings.contains { $0.kind == .unopposed })
    }

    /// Every leak has to carry its mechanics, or the app is complaining.
    @Test func theNewLeakExplainsItself() {
        let note = LeakKind.unopposed.physics
        #expect(note.law.contains("f = μN"))
        #expect(!note.why.isEmpty)
        #expect(!LeakKind.unopposed.drill.isEmpty)
        // And it says what it cannot see, because the wall plane has no depth.
        #expect(note.measured.lowercased().contains("depth"))
    }
}
