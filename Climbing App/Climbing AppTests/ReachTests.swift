import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

private final class BundleToken {}

/// Each hand move, and how much of it the body did.
///
/// Two things are being asserted here. That a hand move is now one event rather
/// than six, and that the share of a reach carried by the body says something
/// different about different moves on the same climb.
@Suite("Reaches")
struct ReachTests {

    private func realClimb() throws -> [PoseFrame] {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "realclimb", withExtension: "json"))
        return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
    }

    // MARK: A move is one move

    /// The shipped detector used one threshold for both leaving and landing, so
    /// a single throw crossed it repeatedly and was reported as several reaches:
    /// 36 in a thirty-second climb, six of them inside half a second.
    ///
    /// Ground truth for this clip is the wrist height series, which is a
    /// staircase with nine or ten steps in it.
    @Test("A thrown hand is one reach, not six")
    func oneThrowIsOneReach() throws {
        let clip = try realClimb()
        let reading = try #require(ReachEngine.read(frames: clip))
        #expect(reading.reaches.count >= 8 && reading.reaches.count <= 12,
                "found \(reading.reaches.count)")

        // No two reaches by the same hand inside the settle window.
        for hand in [JointID.leftWrist, JointID.rightWrist] {
            let byHand = reading.reaches.filter { $0.hand == hand }.map(\.start).sorted()
            for (a, b) in zip(byHand, byHand.dropFirst()) {
                #expect(b - a > ReachEngine.settleSeconds, "two reaches \(b - a)s apart")
            }
        }
    }

    /// The old behaviour, on the same frames, so the fix is a number rather than
    /// a claim. Counted by the rule the old code used: one threshold, no settle.
    @Test("The old rule reports the same climb as three times as many reaches")
    func theOldRuleOverCounts() throws {
        let clip = try realClimb()
        let usable = clip.filter { $0.com != nil }
        let torso = try #require(MetricsEngine.medianTorso(usable))
        let times = usable.map(\.time)

        var oldCount = 0
        for joint in [JointID.leftWrist, JointID.rightWrist] {
            var moving = false
            var launch: CGPoint?
            var previous: CGPoint?
            var previousTime = times.first ?? 0
            for (i, f) in usable.enumerated() {
                guard let p = f.pt(joint) else { previous = nil; continue }
                defer { previous = p; previousTime = times[i] }
                guard let last = previous else { continue }
                let speed = hypot(Double(p.x - last.x), Double(p.y - last.y))
                    / max(times[i] - previousTime, 0.0005)
                if speed > torso * MetricsEngine.reachTorsoPerSecond {
                    if !moving { moving = true; launch = last }
                } else if moving {
                    moving = false
                    if let o = launch,
                       hypot(Double(p.x - o.x), Double(p.y - o.y))
                        > torso * MetricsEngine.reachTorsoDistance { oldCount += 1 }
                    launch = nil
                }
            }
        }
        let now = try #require(ReachEngine.read(frames: clip)).reaches.count
        #expect(oldCount > now * 2, "old \(oldCount), now \(now), so this proves nothing")
    }

    /// One definition of a hand move in the app, not two.
    ///
    /// Not the same count: the contact list includes hands that shuffled on the
    /// hold, because a deadpoint is timed at the moment a hand lands however far
    /// it came, and those are left out of the attribution. But every reach has
    /// to be one of the contacts, or the two are finding different events.
    @Test("The deadpoint detector and the reach reading find the same events")
    func oneDefinitionOfAMove() throws {
        let clip = try realClimb().filter { $0.com != nil }
        let times = clip.map(\.time)
        let contacts = MetricsEngine.handContacts(frames: clip, times: times, joint: .leftWrist)
        let reading = try #require(ReachEngine.read(frames: clip))
        let left = reading.reaches.filter(\.isLeft)

        #expect(contacts.count >= left.count)
        for reach in left {
            #expect(contacts.contains { abs($0 - reach.end) < 0.001 },
                    "the reach ending at \(reach.end) is not in the contact list")
        }
    }

    // MARK: Who did the reaching

    /// A hand that moves while the body stays put: the arm did all of it.
    @Test("An arm-only reach carries none of itself")
    func anArmOnlyReachIsZero() throws {
        var frames: [PoseFrame] = []
        for i in 0..<120 {
            let t = Double(i) / 30
            // The hand sets off at half a second and lands at one second.
            let u = min(max((t - 0.5) / 0.5, 0), 1)
            let wristY = 0.60 - 0.22 * u
            frames.append(still(t: t, wrist: CGPoint(x: 0.44, y: wristY)))
        }
        let reading = try #require(ReachEngine.read(frames: frames + frames.map { shift($0, by: 4) }))
        let reach = try #require(reading.reaches.first)
        #expect(abs(reach.share) < 0.15, "share was \(reach.share)")
    }

    /// The same hand travel, delivered by the whole body moving up the wall.
    @Test("A body-led reach carries all of itself")
    func aBodyLedReachIsOne() throws {
        var frames: [PoseFrame] = []
        for i in 0..<120 {
            let t = Double(i) / 30
            let u = min(max((t - 0.5) / 0.5, 0), 1)
            frames.append(still(t: t, wrist: CGPoint(x: 0.44, y: 0.60 - 0.22 * u),
                                bodyY: -0.22 * u))
        }
        let reading = try #require(ReachEngine.read(frames: frames + frames.map { shift($0, by: 4) }))
        let reach = try #require(reading.reaches.first)
        #expect(reach.share > 0.8, "share was \(reach.share)")
    }

    // MARK: On the real climb

    /// The point of the whole reading: the same climber, thirty seconds apart,
    /// made one reach with their body and one with their arm.
    @Test("The real climb has both kinds in it")
    func therealClimbSpansBothKinds() throws {
        let reading = try #require(ReachEngine.read(frames: try realClimb()))
        let arm = try #require(reading.armLed)
        let body = try #require(reading.bodyLed)

        #expect(arm.share < 0.25, "the least body-led reach was \(arm.share)")
        #expect(body.share > 0.9, "the most body-led reach was \(body.share)")
        #expect(reading.spread >= ReachEngine.worthShowing)
        #expect(arm.start != body.start)

        // Both have to be somewhere a person can go and look.
        for reach in [arm, body] {
            #expect(reach.lookAt >= 0)
            #expect(reach.travelled >= ReachEngine.minimumTravel)
            #expect(!reach.timecode.isEmpty)
        }
    }

    /// Hip openness is self-calibrated, so 1.0 is this climber's own squarest
    /// moment rather than an angle in degrees nobody can measure from one camera.
    @Test("Hip openness is a fraction of this climber's own widest")
    func hipOpennessIsSelfCalibrated() throws {
        let clip = try realClimb()
        let reading = try #require(ReachEngine.read(frames: clip))
        let openness = reading.reaches.compactMap(\.hipOpenness)
        #expect(openness.count >= 5)
        #expect(openness.allSatisfy { $0 > 0 && $0 <= 1 })
        // This climber turns: at least one reach set off well off square.
        #expect(openness.min()! < 0.7)
    }

    /// A tracker that mistakes a wrist for an elbow reports an arm folded double.
    @Test("An impossible elbow is not reported")
    func impossibleElbowsAreDropped() throws {
        let reading = try #require(ReachEngine.read(frames: try realClimb()))
        for reach in reading.reaches {
            if let elbow = reach.catchElbow {
                #expect(elbow >= ReachEngine.plausibleElbow)
                #expect(elbow <= 180)
            }
        }
    }

    // MARK: Building bodies

    /// A whole skeleton standing still, with one wrist placed where asked and
    /// the body optionally shifted up the wall.
    private func still(t: Double, wrist: CGPoint, bodyY: Double = 0) -> PoseFrame {
        func j(_ x: Double, _ y: Double) -> Joint { Joint(x: x, y: y + bodyY, confidence: 0.9) }
        let joints: [JointID: Joint] = [
            .leftShoulder: j(0.46, 0.50), .rightShoulder: j(0.54, 0.50),
            .leftElbow: j(0.44, 0.56), .rightElbow: j(0.56, 0.56),
            .leftWrist: Joint(x: wrist.x, y: wrist.y, confidence: 0.9),
            .rightWrist: j(0.56, 0.60),
            .leftHip: j(0.47, 0.70), .rightHip: j(0.53, 0.70),
            .leftKnee: j(0.46, 0.82), .rightKnee: j(0.54, 0.82),
            .leftAnkle: j(0.45, 0.93), .rightAnkle: j(0.55, 0.93)
        ]
        return PoseFrame(time: t, joints: joints,
                         com: CenterOfMass.estimate(joints: joints), meanConfidence: 0.9)
    }

    /// The same frame later in the clip, so a fixture can hold two reaches.
    private func shift(_ f: PoseFrame, by seconds: Double) -> PoseFrame {
        PoseFrame(time: f.time + seconds, joints: f.joints, com: f.com,
                  meanConfidence: f.meanConfidence)
    }
}

/// The share divides by how far the hand went, so a hand that barely went
/// anywhere makes the ratio meaningless. It is a separate question from whether
/// the hand landed at all.
extension ReachTests {

    @Test("A shuffle on the hold is not attributed to body or arm")
    func aShuffleIsNotAReach() throws {
        let reading = try #require(ReachEngine.read(frames: try realClimbFrames()))
        for reach in reading.reaches {
            #expect(reach.travelled >= ReachEngine.comparableTravel,
                    "a \(reach.travelled) torso move was given a share")
            #expect(reach.share < 2.0, "share of \(reach.share) at \(reach.timecode)")
        }
    }

    /// And the contact itself is still found, because a deadpoint is timed at
    /// the moment a hand lands however far it came.
    @Test("A small hand move is still a contact")
    func aSmallMoveIsStillAContact() throws {
        let clip = try realClimbFrames().filter { $0.com != nil }
        let contacts = MetricsEngine.handContacts(frames: clip, times: clip.map(\.time),
                                                  joint: .rightWrist)
        let reaches = try #require(ReachEngine.read(frames: clip)).reaches.filter { !$0.isLeft }
        #expect(contacts.count > reaches.count,
                "contacts \(contacts.count), reaches \(reaches.count)")
    }

    private func realClimbFrames() throws -> [PoseFrame] {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "realclimb", withExtension: "json"))
        return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
    }
}

/// The base of support is the feet that are on something.
@Suite("Base of support")
struct BaseOfSupportTests {

    private func realClimb() throws -> [PoseFrame] {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "realclimb", withExtension: "json"))
        return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
    }

    /// A foot swinging in space is not holding anybody up, and averaging it into
    /// the base drags the base across the frame with it.
    @Test("A swinging foot is not part of the base")
    func aSwingingFootIsNotPartOfTheBase() {
        var frames: [PoseFrame] = []
        for i in 0..<90 {
            let t = Double(i) / 30
            // The left ankle is bolted to a hold. The right swings through half a
            // torso length and back, twice a second.
            let swing = 0.10 * sin(t * 4 * .pi)
            var joints: [JointID: Joint] = [
                .leftShoulder: Joint(x: 0.46, y: 0.50, confidence: 0.9),
                .rightShoulder: Joint(x: 0.54, y: 0.50, confidence: 0.9),
                .leftHip: Joint(x: 0.47, y: 0.70, confidence: 0.9),
                .rightHip: Joint(x: 0.53, y: 0.70, confidence: 0.9),
                .leftAnkle: Joint(x: 0.45, y: 0.93, confidence: 0.9),
                .rightAnkle: Joint(x: 0.65 + swing, y: 0.93, confidence: 0.9)
            ]
            joints[.leftKnee] = Joint(x: 0.46, y: 0.82, confidence: 0.9)
            joints[.rightKnee] = Joint(x: 0.58, y: 0.82, confidence: 0.9)
            frames.append(PoseFrame(time: t, joints: joints,
                                    com: CenterOfMass.estimate(joints: joints),
                                    meanConfidence: 0.9))
        }

        let bases = MetricsEngine.plantedBase(frames: frames)
        let found = bases.compactMap { $0 }
        #expect(!found.isEmpty)
        // Every base sits on the planted foot, not between it and the swinging one.
        #expect(found.allSatisfy { abs($0 - 0.45) < 0.02 },
                "bases ranged \(found.min() ?? 0) to \(found.max() ?? 0)")

        // The old rule averaged both ankles, so the base moved with the swing.
        let old = frames.compactMap { MetricsEngine.baseOfSupport($0) }
        #expect((old.max() ?? 0) - (old.min() ?? 0) > 0.05,
                "the old base did not move, so this proves nothing")
    }

    /// Both feet on holds is a base between them.
    @Test("Two planted feet make a base between them")
    func twoPlantedFeet() {
        let frames = (0..<90).map { i -> PoseFrame in
            let joints: [JointID: Joint] = [
                .leftShoulder: Joint(x: 0.46, y: 0.50, confidence: 0.9),
                .rightShoulder: Joint(x: 0.54, y: 0.50, confidence: 0.9),
                .leftHip: Joint(x: 0.47, y: 0.70, confidence: 0.9),
                .rightHip: Joint(x: 0.53, y: 0.70, confidence: 0.9),
                .leftAnkle: Joint(x: 0.40, y: 0.93, confidence: 0.9),
                .rightAnkle: Joint(x: 0.60, y: 0.93, confidence: 0.9)
            ]
            return PoseFrame(time: Double(i) / 30, joints: joints,
                             com: CenterOfMass.estimate(joints: joints), meanConfidence: 0.9)
        }
        let bases = MetricsEngine.plantedBase(frames: frames).compactMap { $0 }
        #expect(bases.allSatisfy { abs($0 - 0.50) < 0.01 })
    }

    /// And on the real climb the stricter rule has not thrown the measurement
    /// away.
    ///
    /// A base is found in 43% of frames, which is lower than it sounds: ankles
    /// are the noisiest joint in the clip, with 97th percentile speeds above 20
    /// torso lengths per second, and the plant test rejects a frame whose ankle
    /// is jittering wider than the radius whether or not the foot is on a hold.
    /// What matters is not the share but whether enough still frames survive to
    /// measure, so that is what is asserted.
    @Test("The real climb still has a base under it")
    func therealClimbStillHasABase() throws {
        let clip = try realClimb().filter { $0.com != nil }
        let bases = MetricsEngine.plantedBase(frames: clip)
        let share = Double(bases.compactMap { $0 }.count) / Double(bases.count)
        #expect(share > 0.3, "a base was found in only \(share) of frames")

        let offset = MetricsEngine.comOffsetFromFeet(frames: clip, times: clip.map(\.time))
        #expect(offset > 0, "the offset stopped being measurable")
    }
}
