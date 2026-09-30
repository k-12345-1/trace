import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The five faults from the coaches' list that a pose can see.
///
/// Each test builds the fault and its correct version out of the same
/// skeleton, so what separates them is the one thing the finding claims to
/// measure. The sources are under docs/technique-sources.
@Suite("The coaches' list")
struct CoachesListTests {

    // MARK: A body you can pose

    /// A full skeleton, every joint placed by hand. Torso is 0.20, so a torso
    /// length is 0.20 image units and the engines' thresholds mean what they
    /// say.
    private func pose(t: Double, hipY: Double = 0.55, hipX: Double = 0.50,
                      hipHalfWidth: Double = 0.03,
                      leftElbow: CGPoint? = nil, rightElbow: CGPoint? = nil,
                      leftWrist: CGPoint? = nil, rightWrist: CGPoint? = nil,
                      leftAnkle: CGPoint? = nil, rightAnkle: CGPoint? = nil) -> PoseFrame {
        let shoulderY = hipY - 0.20
        let ls = CGPoint(x: hipX - 0.05, y: shoulderY), rs = CGPoint(x: hipX + 0.05, y: shoulderY)
        let le = leftElbow ?? CGPoint(x: hipX - 0.09, y: shoulderY + 0.08)
        let re = rightElbow ?? CGPoint(x: hipX + 0.09, y: shoulderY + 0.08)
        let lw = leftWrist ?? CGPoint(x: hipX - 0.07, y: shoulderY - 0.12)
        let rw = rightWrist ?? CGPoint(x: hipX + 0.07, y: shoulderY - 0.12)
        let la = leftAnkle ?? CGPoint(x: hipX - 0.04, y: hipY + 0.19)
        let ra = rightAnkle ?? CGPoint(x: hipX + 0.04, y: hipY + 0.19)
        func j(_ p: CGPoint) -> Joint { Joint(x: Double(p.x), y: Double(p.y), confidence: 0.9) }
        let joints: [JointID: Joint] = [
            .leftShoulder: j(ls), .rightShoulder: j(rs),
            .leftElbow: j(le), .rightElbow: j(re),
            .leftWrist: j(lw), .rightWrist: j(rw),
            .leftHip: j(CGPoint(x: hipX - hipHalfWidth, y: hipY)),
            .rightHip: j(CGPoint(x: hipX + hipHalfWidth, y: hipY)),
            .leftKnee: j(CGPoint(x: la.x, y: (hipY + la.y) / 2)),
            .rightKnee: j(CGPoint(x: ra.x, y: (hipY + ra.y) / 2)),
            .leftAnkle: j(la), .rightAnkle: j(ra)
        ]
        return PoseFrame(time: t, joints: joints,
                         com: CGPoint(x: hipX, y: hipY), meanConfidence: 0.9)
    }

    private func ease(_ u: Double) -> Double { 0.5 - 0.5 * cos(u * .pi) }

    // MARK: Reaching before stepping

    /// Three throws of the right hand, 0.6 up each time (three torso lengths),
    /// with the hips and both feet nailed to the wall throughout. The arm did
    /// every one of them.
    private func armOnlyReaches() -> [PoseFrame] {
        var out: [PoseFrame] = []
        var t = 0.0
        var wristY = 0.30
        for _ in 0..<3 {
            for _ in 0..<45 { out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: wristY))); t += 1.0 / 30 }
            let from = wristY, to = wristY - 0.6 / 3
            for i in 1...12 {
                let y = from + (to - from) * ease(Double(i) / 12)
                out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: y))); t += 1.0 / 30
            }
            wristY = to
        }
        for _ in 0..<45 { out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: wristY))); t += 1.0 / 30 }
        return out
    }

    /// The same three throws, but a foot steps up to a new hold a second
    /// before each one.
    private func feetFirstReaches() -> [PoseFrame] {
        var out: [PoseFrame] = []
        var t = 0.0
        var wristY = 0.30
        var footY = 0.74
        for _ in 0..<3 {
            for _ in 0..<20 {
                out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: wristY),
                                leftAnkle: CGPoint(x: 0.46, y: footY))); t += 1.0 / 30
            }
            // The foot goes up a torso length and a bit, which is a step and
            // not an adjustment.
            let footTo = footY - 0.22
            for i in 1...10 {
                let y = footY + (footTo - footY) * ease(Double(i) / 10)
                out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: wristY),
                                leftAnkle: CGPoint(x: 0.46, y: y))); t += 1.0 / 30
            }
            footY = footTo
            for _ in 0..<15 {
                out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: wristY),
                                leftAnkle: CGPoint(x: 0.46, y: footY))); t += 1.0 / 30
            }
            let from = wristY, to = wristY - 0.6 / 3
            for i in 1...12 {
                let y = from + (to - from) * ease(Double(i) / 12)
                out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: y),
                                leftAnkle: CGPoint(x: 0.46, y: footY))); t += 1.0 / 30
            }
            wristY = to
        }
        for _ in 0..<45 {
            out.append(pose(t: t, rightWrist: CGPoint(x: 0.57, y: wristY),
                            leftAnkle: CGPoint(x: 0.46, y: footY))); t += 1.0 / 30
        }
        return out
    }

    @Test("Reaching with the feet still is named")
    func armOnlyReachesAreNamed() {
        let reading = TechniqueEngine.read(frames: armOnlyReaches())
        #expect(reading.upwardReaches.count >= 3, "found \(reading.upwardReaches.count) upward reaches")
        #expect(reading.feetStayed.count == reading.upwardReaches.count)
        let findings = FindingEngine.techniqueFindings(frames: armOnlyReaches())
        #expect(findings.contains { $0.kind == .overReaching })
    }

    @Test("A foot moved first is not over-reaching")
    func feetFirstIsNot() {
        let reading = TechniqueEngine.read(frames: feetFirstReaches())
        #expect(reading.upwardReaches.count >= 3, "found \(reading.upwardReaches.count) upward reaches")
        #expect(reading.steps.count >= 3, "found \(reading.steps.count) steps")
        #expect(reading.feetStayed.isEmpty, "\(reading.feetStayed.count) reaches were called arm-only")
        #expect(!FindingEngine.techniqueFindings(frames: feetFirstReaches())
                    .contains { $0.kind == .overReaching })
    }

    // MARK: Holding a lock-off

    /// A right arm folded to about seventy degrees and held there on its hold.
    private func heldLockOff(seconds: Double) -> [PoseFrame] {
        (0..<Int(seconds * 30)).map { i in
            pose(t: Double(i) / 30,
                 rightElbow: CGPoint(x: 0.59, y: 0.43),
                 rightWrist: CGPoint(x: 0.49, y: 0.47))
        }
    }

    @Test("The fixture's arm really is locked off")
    func theLockOffFixtureIsBent() throws {
        let f = try #require(heldLockOff(seconds: 1).first)
        let s = try #require(f.pt(.rightShoulder)), e = try #require(f.pt(.rightElbow)),
            w = try #require(f.pt(.rightWrist))
        let angle = MetricsEngine.angle(at: e, from: s, to: w)
        let locked = angle > MetricsEngine.plausibleElbow && angle < TechniqueEngine.lockOffAngle
        #expect(locked, "elbow was \(angle) degrees")
    }

    @Test("A lock-off held for three seconds is named, one flowed through is not")
    func heldLockOffsAreNamed() {
        let held = TechniqueEngine.read(frames: heldLockOff(seconds: 3.2))
        #expect(held.lockOffHeldSeconds >= TechniqueEngine.lockOffHeld,
                "longest was \(held.lockOffHeldSeconds)")
        #expect(FindingEngine.techniqueFindings(frames: heldLockOff(seconds: 3.2))
                    .contains { $0.kind == .lockOffHeld })

        let brief = TechniqueEngine.read(frames: heldLockOff(seconds: 1.2))
        #expect(brief.lockOffs.isEmpty)

        let straight = TechniqueEngine.read(frames: (0..<100).map { pose(t: Double($0) / 30) })
        #expect(straight.lockOffs.isEmpty, "a hanging arm was called a lock-off")
    }

    // MARK: Elbows flared

    @Test("An elbow above its shoulder with the hand below is a flare")
    func flaredElbowIsNamed() {
        // Right elbow 0.04 above the shoulder (0.2 torso), hand at chest height.
        let flared = (0..<60).map { i in
            pose(t: Double(i) / 30,
                 rightElbow: CGPoint(x: 0.62, y: 0.31),
                 rightWrist: CGPoint(x: 0.55, y: 0.42))
        }
        let reading = TechniqueEngine.read(frames: flared)
        #expect(reading.flaredSeconds >= TechniqueEngine.flareHeld, "flared for \(reading.flaredSeconds)")
        #expect(FindingEngine.techniqueFindings(frames: flared).contains { $0.kind == .elbowsFlared })

        let tucked = TechniqueEngine.read(frames: (0..<60).map { pose(t: Double($0) / 30) })
        #expect(tucked.flares.isEmpty)
    }

    // MARK: Stepping too high

    /// Three steps of the left foot to `landing` and back. Both legs are
    /// about a torso long, so the step has to cover at least 0.9 of one to be
    /// a step rather than an adjustment; `landing` decides how high it is.
    private func steps(landing: CGPoint) -> [PoseFrame] {
        var out: [PoseFrame] = []
        var t = 0.0
        let home = CGPoint(x: 0.46, y: 0.74)
        let other = CGPoint(x: 0.54, y: 0.74)
        func hold(_ p: CGPoint, _ n: Int) {
            for _ in 0..<n { out.append(pose(t: t, leftAnkle: p, rightAnkle: other)); t += 1.0 / 30 }
        }
        func move(_ a: CGPoint, _ b: CGPoint) {
            for i in 1...10 {
                let u = ease(Double(i) / 10)
                out.append(pose(t: t, leftAnkle: CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u),
                                rightAnkle: other)); t += 1.0 / 30
            }
        }
        for _ in 0..<3 {
            hold(home, 20); move(home, landing); hold(landing, 20); move(landing, home)
        }
        hold(home, 20)
        return out
    }

    @Test("A foot landing at hip height is a high step; a knee-height one is not")
    func highStepsAreNamed() {
        // Straight up to a tenth of a torso below the hips at 0.55.
        let up = CGPoint(x: 0.40, y: 0.57)
        let high = TechniqueEngine.read(frames: steps(landing: up))
        #expect(high.steps.count >= 3, "found \(high.steps.count) steps")
        #expect(high.highSteps.count >= 2, "\(high.highSteps.count) high")
        #expect(FindingEngine.techniqueFindings(frames: steps(landing: up)).contains { $0.kind == .highStep })

        // The same distance mostly sideways, landing half a torso below the
        // hips: knee height, which is a step and not a high one.
        let across = CGPoint(x: 0.28, y: 0.66)
        let modest = TechniqueEngine.read(frames: steps(landing: across))
        #expect(modest.steps.count >= 3, "found \(modest.steps.count) steps")
        #expect(modest.highSteps.isEmpty, "\(modest.highSteps.count) knee-height steps were called high")
    }

    // MARK: Square hips

    /// Hips at full width for the whole climb and every catch on a bent arm.
    ///
    /// The hand throws up a torso length, catches with the elbow out beside
    /// the shoulder, and then the body climbs up to it: the shape of a climber
    /// who pulls square every move. The hips never narrow, so their openness
    /// against their own widest is one on every reach.
    private func squareBentReaches() -> [PoseFrame] {
        var out: [PoseFrame] = []
        var t = 0.0
        var hipY = 0.85
        func frame(handAbove: Double, hipY: Double) -> PoseFrame {
            let s = hipY - 0.20
            return pose(t: t, hipY: hipY, hipHalfWidth: 0.06,
                        rightElbow: CGPoint(x: 0.63, y: s + 0.02),
                        rightWrist: CGPoint(x: 0.55, y: s - handAbove))
        }
        for _ in 0..<3 {
            for _ in 0..<45 { out.append(frame(handAbove: 0.10, hipY: hipY)); t += 1.0 / 30 }
            // The hand goes first, a torso length up.
            for i in 1...12 {
                out.append(frame(handAbove: 0.10 + 0.20 * ease(Double(i) / 12), hipY: hipY)); t += 1.0 / 30
            }
            for _ in 0..<15 { out.append(frame(handAbove: 0.30, hipY: hipY)); t += 1.0 / 30 }
            // Then the body follows it, the hand staying where it caught.
            let from = hipY, to = hipY - 0.20
            for i in 1...15 {
                let y = from + (to - from) * ease(Double(i) / 15)
                out.append(frame(handAbove: 0.30 - (from - y), hipY: y)); t += 1.0 / 30
            }
            hipY = to
        }
        for _ in 0..<45 { out.append(frame(handAbove: 0.10, hipY: hipY)); t += 1.0 / 30 }
        return out
    }

    @Test("Square hips with a bent catch are named")
    func squareHipsAreNamed() {
        let reading = TechniqueEngine.read(frames: squareBentReaches())
        #expect(reading.hipJudged >= 3, "judged \(reading.hipJudged)")
        #expect(reading.squareAndBent.count >= 2, "\(reading.squareAndBent.count) square and bent")
        #expect(FindingEngine.techniqueFindings(frames: squareBentReaches()).contains { $0.kind == .squareHips })
    }

    // MARK: Old climbs still decode

    @Test("A climb saved before these measurements still loads")
    func oldMetricsDecode() throws {
        let json = """
        {"entropy":0.5,"logJerk":1,"pathRatio":1.1,"staticElbowAngle":160,"pauseCount":0,
         "pauseTotal":0,"footAdjustments":0,"comPath":[],"duration":10,"trackingConfidence":0.9}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(Metrics.self, from: json)
        #expect(m.feetStayedShare == nil)
        #expect(m.lockOffHeldSeconds == 0)
        #expect(m.highStepShare == nil)
    }

    // MARK: Nothing fires on a clean climb

    @Test("A straight ascent with straight arms raises none of these")
    func aCleanClimbIsClean() {
        let findings = FindingEngine.techniqueFindings(frames: Fixture.straightAscent())
        #expect(findings.isEmpty, "\(findings.map(\.kind))")
    }
}
