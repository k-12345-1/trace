import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The four defects the first real clip exposed, each pinned so it cannot come
/// back. Every fixture here is built from geometry, so the expected answer is
/// known without running the code first.
@Suite("Foot precision")
struct FootPrecisionTests {

    /// An ankle at rest, jittering by the amount Vision jitters, with a torso of
    /// 0.20. The old detector counted one adjustment per jitter cycle and
    /// returned 41 on a thirteen second boulder; a planted foot must return none.
    @Test func trackerJitterIsNotAFootAdjustment() {
        let frames = (0..<300).map { i -> PoseFrame in
            let wobble = (i % 2 == 0 ? 1.0 : -1.0) * 0.004
            return Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: 0.5 + wobble,
                                wrist: CGPoint(x: 0.5, y: 0.3))
        }
        #expect(MetricsEngine.footAdjustments(frames: frames) == 0)
    }

    /// One foot placed, shuffled a short distance, and replaced. One adjustment.
    ///
    /// Only the left ankle moves. A fixture that slides the whole body sideways
    /// moves both feet and scores two, which is the fixture being wrong rather
    /// than the detector.
    @Test func aShortShuffleCounts() {
        let frames = (0..<70).map { i -> PoseFrame in
            // Planted, a four frame hop of a fifth of a torso, planted again.
            let x: Double = i < 30 ? 0.50 : i < 34 ? 0.50 + 0.01 * Double(i - 29) : 0.54
            return oneFootMoved(t: Double(i) / 30, leftAnkleX: x)
        }
        #expect(MetricsEngine.footAdjustments(frames: frames) == 1)
    }

    /// A body with the right foot planted and the left where you put it.
    private func oneFootMoved(t: Double, leftAnkleX: Double) -> PoseFrame {
        let base = Fixture.body(t: t, comY: 0.5, feetX: 0.5,
                                wrist: CGPoint(x: 0.5, y: 0.3))
        var joints = base.joints
        joints[.leftAnkle] = Fixture.joint(leftAnkleX, 0.69)
        return PoseFrame(time: t, joints: joints, com: base.com, meanConfidence: 0.9)
    }

    /// The same movement, but the foot travels a whole torso length to a new
    /// hold. That is a placement, not a correction, and must not be counted.
    @Test func aRealMoveToANewHoldIsNotAnAdjustment() {
        var frames: [PoseFrame] = []
        for i in 0..<30 {
            frames.append(Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: 0.30,
                                       wrist: CGPoint(x: 0.5, y: 0.3)))
        }
        for i in 30..<40 {
            let x = 0.30 + 0.025 * Double(i - 29)
            frames.append(Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: x,
                                       wrist: CGPoint(x: 0.5, y: 0.3)))
        }
        for i in 40..<80 {
            frames.append(Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: 0.55,
                                       wrist: CGPoint(x: 0.5, y: 0.3)))
        }
        #expect(MetricsEngine.footAdjustments(frames: frames) == 0)
    }

    /// Distances are in torso lengths, so the same climber filmed further away
    /// scores the same. The old detector compared raw image units to a constant
    /// and got twice as sensitive every time the phone moved back.
    @Test func theCountSurvivesTheCameraMovingBack() {
        func clip(scale k: Double) -> [PoseFrame] {
            (0..<70).map { i -> PoseFrame in
                let x: Double = i < 30 ? 0.50 : i < 34 ? 0.50 + 0.01 * Double(i - 29) : 0.54
                let f = oneFootMoved(t: Double(i) / 30, leftAnkleX: x)
                // The whole body shrinks toward the middle of the frame, which is
                // exactly what moving the phone back does.
                var joints: [JointID: Joint] = [:]
                for (id, j) in f.joints {
                    joints[id] = Joint(x: 0.5 + (j.x - 0.5) * k,
                                       y: 0.5 + (j.y - 0.5) * k, confidence: j.confidence)
                }
                return PoseFrame(time: f.time, joints: joints,
                                 com: CGPoint(x: 0.5, y: 0.5), meanConfidence: 0.9)
            }
        }
        #expect(MetricsEngine.footAdjustments(frames: clip(scale: 1.0)) == 1)
        #expect(MetricsEngine.footAdjustments(frames: clip(scale: 0.5)) == 1)
    }
}

@Suite("Smoothness is relative")
struct SmoothnessTests {

    /// A first climb has no history, so nothing can be said about whether it was
    /// rough for this climber. The old fixed threshold fired on every real clip.
    @Test func noHistoryMeansNoJudgement() {
        #expect(FindingEngine.jerkExcess(23.2, over: []) == nil)
        #expect(FindingEngine.jerkExcess(23.2, over: [21.0, 21.5]) == nil)
    }

    @Test func anAttemptInLineWithYourOwnIsNotFlagged() {
        #expect(FindingEngine.jerkExcess(21.2, over: [21.0, 21.3, 21.1, 20.9]) == nil)
    }

    @Test func aRougherThanUsualAttemptIsFlagged() {
        let excess = FindingEngine.jerkExcess(22.5, over: [21.0, 21.3, 21.1, 20.9])
        #expect(excess != nil)
        #expect((excess ?? 0) > 1.0)
    }

    /// Untracked climbs come through as a zero and must not drag the median.
    @Test func zerosAreNotHistory() {
        #expect(FindingEngine.jerkExcess(23.0, over: [0, 0, 0, 21.0]) == nil)
    }

    /// Jerk is a third derivative, so at the capture rate the same movement
    /// filmed at two frame rates scored differently and the difference was all
    /// noise. Resampling first is what makes two attempts comparable.
    @Test func theSameMovementScoresTheSameAtTwoFrameRates() {
        func path(rate: Double) -> (p: [CGPoint], t: [Double]) {
            let duration = 3.0
            let n = Int(duration * rate)
            var p: [CGPoint] = [], t: [Double] = []
            for i in 0...n {
                let time = Double(i) / rate
                // A smooth arc, identical in shape whatever the sampling.
                p.append(CGPoint(x: 0.5 + 0.1 * sin(time), y: 0.8 - 0.1 * time))
                t.append(time)
            }
            return (p, t)
        }
        let a = path(rate: 30), b = path(rate: 60)
        let ja = MetricsEngine.logDimensionlessJerk(
            path: a.p, times: a.t, length: MetricsEngine.pathLength(a.p))
        let jb = MetricsEngine.logDimensionlessJerk(
            path: b.p, times: b.t, length: MetricsEngine.pathLength(b.p))
        #expect(abs(ja - jb) < 0.5)
    }

    @Test func resamplingLandsOnAnEvenGrid() {
        let times = [0.0, 0.03, 0.09, 0.11, 0.2]
        let path = times.map { CGPoint(x: $0, y: 0) }
        let out = MetricsEngine.resample(path: path, times: times, rate: 10)
        #expect(out.count == 3)                       // 0.0, 0.1, 0.2
        #expect(abs(Double(out[1].x) - 0.1) < 0.02)   // linear between samples
    }
}

@Suite("Findings point at a moment")
struct FindingWindowTests {

    /// Every finding used to arrive at 0:00, which made tapping one useless.
    /// A climb with no pause in it was the case that broke the old window
    /// finder, so that is the case tested here.
    @Test func findingsCarryARealWindowOnAClimbWithNoPauses() {
        let frames = Fixture.straightAscent(count: 120)
        let metrics = MetricsEngine.compute(frames: frames)
        #expect(metrics.pauseCount == 0)

        let findings = FindingEngine.findings(from: metrics, frames: frames)
        for f in findings {
            #expect(f.end > f.start, "\(f.kind.title) has an empty window")
            #expect(f.end <= metrics.duration + 0.01)
        }
    }

    @Test func theBentArmWindowLandsOnTheBentArms() {
        // Straight arms for two seconds, then bent arms for two.
        var frames: [PoseFrame] = []
        for i in 0..<120 {
            let bent = i >= 60
            let shoulder = bent ? CGPoint(x: 0.60, y: 0.50) : CGPoint(x: 0.50, y: 0.60)
            let joints: [JointID: Joint] = [
                .leftShoulder: Fixture.joint(shoulder.x, shoulder.y),
                .rightShoulder: Fixture.joint(shoulder.x, shoulder.y),
                .leftElbow: Fixture.joint(0.50, 0.50), .rightElbow: Fixture.joint(0.50, 0.50),
                .leftWrist: Fixture.joint(0.50, 0.40), .rightWrist: Fixture.joint(0.50, 0.40)
            ]
            frames.append(PoseFrame(time: Double(i) / 30, joints: joints,
                                    com: CGPoint(x: 0.5, y: 0.5), meanConfidence: 0.9))
        }
        let window = FindingEngine.worstStaticElbowWindow(frames: frames)
        #expect(window != nil)
        #expect((window?.start ?? 0) >= 1.9, "should land in the bent half")
    }

    @Test func theOffsetWindowLandsOnTheWorstLean() {
        var frames: [PoseFrame] = []
        for i in 0..<120 {
            // Hips drift far out to the side for one second in the middle.
            let out = (i >= 45 && i < 75) ? 0.18 : 0.01
            frames.append(Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: 0.5,
                                       wrist: CGPoint(x: 0.5, y: 0.3),
                                       hipX: 0.5 + out))
        }
        let window = FindingEngine.worstOffsetWindow(frames: frames)
        #expect(window != nil)
        #expect((window?.start ?? 0) >= 1.0)
        #expect((window?.end ?? 99) <= 3.0)
    }
}

@Suite("Weight on arms needs enough stillness")
struct StillnessTests {

    /// A single near-still frame is not a measurement of how someone rests.
    @Test func aHandfulOfStillFramesSaysNothing() {
        var frames: [PoseFrame] = []
        // Moving fast throughout, apart from three frames.
        for i in 0..<120 {
            let still = (i >= 50 && i < 53)
            let x = still ? 0.5 : 0.5 + Double(i) * 0.02
            frames.append(Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: 0.5,
                                       wrist: CGPoint(x: 0.5, y: 0.3), hipX: x))
        }
        let times = frames.map { $0.time }
        #expect(MetricsEngine.comOffsetFromFeet(frames: frames, times: times) == 0)
    }

    /// Half a second of it is enough, and then the number is real.
    @Test func halfASecondOfStillnessIsEnough() {
        let frames = (0..<120).map { i in
            Fixture.body(t: Double(i) / 30, comY: 0.5, feetX: 0.5,
                         wrist: CGPoint(x: 0.5, y: 0.3), hipX: 0.60)
        }
        let times = frames.map { $0.time }
        let offset = MetricsEngine.comOffsetFromFeet(frames: frames, times: times)
        // In hip widths now, and measured from the span of the feet rather than
        // their midpoint. What this test is about is the sample count: half a
        // second of stillness is enough for the number to be reported at all.
        #expect(offset > 0.5, "half a second of stillness reported \(offset)")
    }
}
