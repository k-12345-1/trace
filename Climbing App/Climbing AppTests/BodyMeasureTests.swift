import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

private final class MeasureToken {}

/// The figure's proportions, read off the climber's own footage.
@Suite("Measuring the body")
struct BodyMeasureTests {

    /// A body with known proportions, waving its arms about so that every
    /// limb is foreshortened in most frames and flat in a few.
    private func frames(upper: Double = 0.10, fore: Double = 0.09, shoulders: Double = 0.12,
                        hips: Double = 0.08, torso: Double = 0.16, thigh: Double = 0.13,
                        shin: Double = 0.12, count: Int = 120) -> [PoseFrame] {
        (0..<count).map { i in
            // Foreshortening: a factor between 0.4 and 1 that reaches 1 at
            // least a few times across the clip.
            let f = 0.4 + 0.6 * abs(sin(Double(i) * 0.37))
            let g = 0.4 + 0.6 * abs(cos(Double(i) * 0.23))
            func j(_ x: Double, _ y: Double) -> Joint { Joint(x: x, y: y, confidence: 0.9) }
            let c = CGPoint(x: 0.5, y: 0.5)
            var joints: [JointID: Joint] = [:]
            joints[.leftShoulder] = j(c.x - shoulders / 2, c.y)
            joints[.rightShoulder] = j(c.x + shoulders / 2, c.y)
            joints[.nose] = j(c.x, c.y - 0.07)
            joints[.leftElbow] = j(c.x - shoulders / 2 - upper * f, c.y)
            joints[.rightElbow] = j(c.x + shoulders / 2 + upper * g, c.y)
            joints[.leftWrist] = j(c.x - shoulders / 2 - upper * f - fore * g, c.y)
            joints[.rightWrist] = j(c.x + shoulders / 2 + upper * g + fore * f, c.y)
            joints[.leftHip] = j(c.x - hips / 2, c.y + torso)
            joints[.rightHip] = j(c.x + hips / 2, c.y + torso)
            joints[.leftKnee] = j(c.x - hips / 2, c.y + torso + thigh * g)
            joints[.rightKnee] = j(c.x + hips / 2, c.y + torso + thigh * f)
            joints[.leftAnkle] = j(c.x - hips / 2, c.y + torso + thigh * g + shin * f)
            joints[.rightAnkle] = j(c.x + hips / 2, c.y + torso + thigh * f + shin * g)
            return PoseFrame(time: Double(i) / 30, joints: joints, com: CGPoint(x: 0.5, y: 0.6), meanConfidence: 0.9)
        }
    }

    @Test func theLengthsComeBackNearlyTrue() throws {
        let l = try #require(BodyMeasure.lengths(in: frames()))
        #expect(abs(l.upperArm - 0.10) < 0.012, "\(l.upperArm)")
        #expect(abs(l.forearm - 0.09) < 0.012, "\(l.forearm)")
        #expect(abs(l.shoulderWidth - 0.12) < 0.005)
        #expect(abs(l.thigh - 0.13) < 0.015)
        #expect(abs(l.shin - 0.12) < 0.015)
    }

    /// The defect this exists for: the figure used to be the average body for
    /// everyone. A long-armed, narrow-shouldered climber now gets that body.
    @Test func theShapeIsThisBodysNotTheAverage() throws {
        let s = try #require(BodyMeasure.shape(from: frames(upper: 0.12, fore: 0.11, shoulders: 0.09)))
        #expect(s.measured)
        #expect(s.arm > BetaEngine.Shape.average.arm)
        #expect(s.shoulderWidth < BetaEngine.Shape.average.shoulderWidth)
        // Shares of the span add up to the span.
        #expect(abs(2 * s.arm + s.shoulderWidth - 1) < 0.02)
    }

    @Test func tooLittleFootageSaysNothing() {
        #expect(BodyMeasure.shape(from: frames(count: 20)) == nil)
        #expect(BodyMeasure.shape(from: []) == nil)
    }

    /// A misplaced joint in a few frames cannot give the figure a leg to match.
    @Test func aTrackerSpikeIsNotALimb() throws {
        var f = frames()
        for i in 0..<5 { f[i].joints[.leftAnkle] = Joint(x: 0.5, y: 2.0, confidence: 0.9) }
        let s = try #require(BodyMeasure.shape(from: f))
        #expect(s.shin <= 0.30)
    }

    @Test func theRealClimberHasABody() throws {
        let url = try #require(Bundle(for: MeasureToken.self).url(forResource: "realclimb", withExtension: "json"))
        let clip = try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
        let s = try #require(BodyMeasure.shape(from: clip))
        #expect(s.measured)
        #expect(s.arm > 0.3 && s.arm < 0.48, "\(s.arm)")
        #expect(s.leg > 0.34 && s.leg < 0.62, "\(s.leg)")
        // And the figure still stands on the real route with it.
        let line = try #require(LineEngine.read(holds: [
            CGRect(x: 0.4, y: 0.8, width: 0.05, height: 0.05),
            CGRect(x: 0.5, y: 0.65, width: 0.05, height: 0.05),
            CGRect(x: 0.45, y: 0.5, width: 0.05, height: 0.05),
            CGRect(x: 0.5, y: 0.35, width: 0.05, height: 0.05)]))
        let seq = BetaEngine.read(line: line, shape: s)
        #expect(seq != nil)
        for p in seq?.stances ?? [] { for j in p.joints { #expect(j.x.isFinite && j.y.isFinite) } }
    }
}
