import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

// MARK: - Geometry and smoothness

@Suite("Movement metrics")
struct MovementMetricsTests {

    @Test("A perfectly straight path has zero entropy")
    func straightPathEntropy() {
        let path = Fixture.straightPath()
        let h = MetricsEngine.geometricEntropy(path: path,
                                               length: MetricsEngine.pathLength(path))
        // ln(2L / 2L) = 0, because the hull of a collinear set is the line doubled back.
        #expect(abs(h) < 0.001)
    }

    @Test("A closed circle has entropy of ln 2")
    func circleEntropy() {
        let path = Fixture.circlePath()
        let h = MetricsEngine.geometricEntropy(path: path,
                                               length: MetricsEngine.pathLength(path))
        #expect(abs(h - log(2.0)) < 0.01)
    }

    @Test("A wandering path scores well above a straight one")
    func zigzagEntropy() {
        let zig = (0..<40).map { i in
            CGPoint(x: 0.5 + (i % 2 == 0 ? 0.12 : -0.12), y: 0.9 - Double(i) * 0.02)
        }
        let h = MetricsEngine.geometricEntropy(path: zig,
                                               length: MetricsEngine.pathLength(zig))
        #expect(h > 0.5)
    }

    @Test("The convex hull of a noisy square is its four corners")
    func convexHull() {
        var pts: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                              CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        pts += (0..<30).map { _ in
            CGPoint(x: Double.random(in: 0.2...0.8), y: Double.random(in: 0.2...0.8))
        }
        #expect(MetricsEngine.convexHull(pts).count == 4)
    }

    @Test("Joint angles are measured in degrees")
    func angles() {
        let right = MetricsEngine.angle(at: CGPoint(x: 0, y: 0),
                                        from: CGPoint(x: 1, y: 0), to: CGPoint(x: 0, y: 1))
        let flat = MetricsEngine.angle(at: CGPoint(x: 0, y: 0),
                                       from: CGPoint(x: -1, y: 0), to: CGPoint(x: 1, y: 0))
        #expect(abs(right - 90) < 0.001)
        #expect(abs(flat - 180) < 0.001)
    }

    @Test("Bent arms held still measure 90 degrees, straight arms 180")
    func staticElbow() {
        let (bent, bentTimes) = Fixture.arms(bent: true)
        let (straight, straightTimes) = Fixture.arms(bent: false)
        #expect(abs(MetricsEngine.staticElbow(frames: bent, times: bentTimes) - 90) < 0.5)
        #expect(abs(MetricsEngine.staticElbow(frames: straight, times: straightTimes) - 180) < 0.5)
    }

    @Test("A motionless climber is one long pause")
    func pauses() {
        let path = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 60)
        let times = (0..<60).map { Double($0) / 30 }
        let stops = MetricsEngine.pauses(path: path, times: times)
        #expect(stops.count == 1)
        #expect((stops.first.map { $0.end - $0.start } ?? 0) > 1.8)
    }

    @Test("The whole pipeline agrees on a straight ascent")
    func pipeline() {
        let m = MetricsEngine.compute(frames: Fixture.straightAscent())
        #expect(abs(m.pathRatio - 1.0) < 0.02)
        #expect(abs(m.entropy) < 0.02)
        #expect(abs(m.trackingConfidence - 1.0) < 0.001)
        #expect(m.isTrustworthy)
    }
}

// MARK: - Center of mass

@Suite("Center of mass")
struct CenterOfMassTests {

    @Test("A symmetric body has its center of mass on the midline")
    func symmetric() {
        let joints = Fixture.straightAscent()[0].joints
        let com = CenterOfMass.estimate(joints: joints)
        #expect(com != nil)
        #expect(abs(Double(com?.x ?? 0) - 0.5) < 0.005)
    }

    @Test("A sparse skeleton yields nothing rather than a bad guess")
    func sparse() {
        // Confidently wrong output is the failure mode that kills the product,
        // so too little of the body present must produce no answer at all.
        let sparse: [JointID: Joint] = [.leftWrist: Fixture.joint(0.1, 0.1)]
        #expect(CenterOfMass.estimate(joints: sparse) == nil)
    }
}

// MARK: - Weight on arms

@Suite("Weight on arms")
struct WeightOnArmsTests {

    @Test("Torso length and base of support are measured from the skeleton")
    func references() {
        let f = Fixture.body(t: 0, comY: 0.5, feetX: 0.5, wrist: CGPoint(x: 0.5, y: 0.35))
        #expect(abs((MetricsEngine.torsoLength(f) ?? 0) - 0.20) < 0.005)
        #expect(abs((MetricsEngine.baseOfSupport(f) ?? -1) - 0.5) < 0.001)
    }

    @Test("A climber stacked over their feet has no offset")
    func stacked() {
        let frames = (0..<60).map {
            Fixture.body(t: Double($0) / 30, comY: 0.5, feetX: 0.5,
                         wrist: CGPoint(x: 0.5, y: 0.35))
        }
        let offset = MetricsEngine.comOffsetFromFeet(frames: frames,
                                                     times: frames.map(\.time))
        #expect(offset < 0.01)
    }

    @Test("Hips a tenth of a frame out read as half a torso length")
    func hanging() {
        // Torso is 0.20 by construction and the hips sit 0.10 out, so the answer
        // is exactly 0.5 torso lengths.
        let frames = (0..<60).map {
            Fixture.body(t: Double($0) / 30, comY: 0.5, feetX: 0.5,
                         wrist: CGPoint(x: 0.6, y: 0.35), hipX: 0.6)
        }
        let offset = MetricsEngine.comOffsetFromFeet(frames: frames,
                                                     times: frames.map(\.time))
        #expect(abs(offset - 0.5) < 0.02)
    }
}

// MARK: - Deadpoint timing

@Suite("Deadpoint timing")
struct DeadpointTests {

    /// A body thrown upward and falling back, with a hand that travels to a new
    /// hold and settles right at the top of the arc.
    private func throwWithCatch() -> ([PoseFrame], [Double]) {
        let times = (0..<61).map { Double($0) / 60 }
        let frames = times.map { t -> PoseFrame in
            // y grows downward, so subtracting the parabola makes the body rise.
            let comY = 0.7 - (0.3 - 1.2 * pow(t - 0.5, 2))
            let wristX: Double
            if t < 0.3 { wristX = 0.40 }
            else if t < 0.5 { wristX = 0.40 + (t - 0.3) / 0.2 * 0.12 }
            else { wristX = 0.52 }
            return Fixture.body(t: t, comY: comY, feetX: 0.5,
                                wrist: CGPoint(x: wristX, y: 0.35))
        }
        return (frames, times)
    }

    @Test("A single throw has exactly one apex, at the top of the arc")
    func apex() {
        let (frames, times) = throwWithCatch()
        let apexes = MetricsEngine.verticalApexes(path: frames.compactMap(\.com), times: times)
        #expect(apexes.count == 1)
        #expect(abs((apexes.first ?? -1) - 0.5) < 0.05)
    }

    @Test("A hand thrown to a new hold registers one contact")
    func contact() {
        let (frames, times) = throwWithCatch()
        let contacts = MetricsEngine.handContacts(frames: frames, times: times,
                                                  joint: .leftWrist)
        #expect(contacts.count == 1)
    }

    @Test("A catch at the apex scores near zero timing error")
    func wellTimed() {
        let (frames, times) = throwWithCatch()
        let offsets = MetricsEngine.deadpointOffsets(frames: frames, times: times)
        #expect(!offsets.isEmpty)
        #expect(offsets.allSatisfy { abs($0) < 0.10 })
    }

    @Test("A static climb reports no dynamic moves rather than perfect timing")
    func staticClimbClaimsNothing() {
        // Zero milliseconds would read as a flawless deadpoint. Nothing measured
        // is the honest answer.
        let times = (0..<60).map { Double($0) / 30 }
        let frames = times.map {
            Fixture.body(t: $0, comY: 0.5, feetX: 0.5, wrist: CGPoint(x: 0.5, y: 0.35))
        }
        #expect(MetricsEngine.deadpointOffsets(frames: frames, times: times).isEmpty)

        let m = MetricsEngine.compute(frames: frames)
        #expect(!m.hasDynamicMoves)
        #expect(m.meanDeadpointError == 0)
    }
}

// MARK: - Findings

@Suite("Findings")
struct FindingTests {

    @Test("Every leak the app can measure is reachable")
    func allLeaksReachable() {
        var m = Fixture.metrics(entropy: 1.6, elbow: 118, jerk: 13, ratio: 2.4, feet: 9,
                                offset: 0.75, deadpoints: [0.31, 0.28, 0.35],
                                moveWaste: 0.45)
        m.pauseTotal = 15
        m.pauseCount = 4
        // Smoothness is judged against the climber's own history, so lurchy is
        // only reachable when there is one. A median of 11 makes 13 rough.
        let found = Set(FindingEngine.findings(from: m, frames: [],
                                               priorJerk: [10.8, 11.0, 11.2, 11.1])
            .map(\.kind))
        for kind in [LeakKind.bentArms, .weightOnArms, .lurchy,
                     .impreciseFeet, .hesitation, .wandering, .mistimedDynamics] {
            #expect(found.contains(kind), "\(kind.rawValue) was never produced")
        }
    }

    @Test("Late catches are described as late")
    func deadpointDirection() {
        let m = Fixture.metrics(deadpoints: [0.31, 0.28, 0.35])
        let finding = FindingEngine.findings(from: m, frames: [])
            .first { $0.kind == .mistimedDynamics }
        #expect(finding?.message.contains("late") == true)
    }

    @Test("Nothing is said about a clip that could not be tracked")
    func untrustedSaysNothing() {
        let m = Fixture.metrics(elbow: 100, offset: 0.9, confidence: 0.2)
        #expect(!m.isTrustworthy)
        #expect(FindingEngine.findings(from: m, frames: []).isEmpty)
    }

    @Test("Findings are ranked with the most expensive first")
    func ranking() {
        let m = Fixture.metrics(entropy: 1.6, elbow: 110, ratio: 1.45, feet: 4, offset: 0.4)
        let findings = FindingEngine.findings(from: m, frames: [])
        #expect(findings.count > 1)
        #expect(zip(findings, findings.dropFirst()).allSatisfy { $0.severity >= $1.severity })
    }
}

// MARK: - Beta clustering

@Suite("Beta clustering")
struct BetaClusteringTests {

    @Test("Resampling returns a fixed number of points")
    func resample() {
        #expect(BetaClustering.resample(Fixture.sPath(), to: 32).count == 32)
    }

    @Test("Shape comparison ignores where the climber stood and how big they looked")
    func invariance() {
        let a = Fixture.sPath()
        let moved = a.map { CGPoint(x: $0.x * 0.6 + 0.2, y: $0.y * 0.6 + 0.1) }
        #expect(BetaClustering.shapeDistance(a, a) < 0.001)
        #expect(BetaClustering.shapeDistance(a, moved) < 0.05)
    }

    @Test("Tracking noise does not look like a different sequence")
    func noiseTolerated() {
        let a = Fixture.sPath()
        let noisy = a.map {
            CGPoint(x: Double($0.x) + Double.random(in: -0.004...0.004),
                    y: Double($0.y) + Double.random(in: -0.004...0.004))
        }
        #expect(BetaClustering.shapeDistance(a, noisy) < BetaClustering.sameSequenceThreshold)
    }

    @Test("A genuinely different sequence separates")
    func differentSequences() {
        let straight = (0..<60).map { CGPoint(x: 0.5, y: 0.9 - Double($0) / 59 * 0.7) }
        #expect(BetaClustering.shapeDistance(Fixture.sPath(), straight)
                > BetaClustering.sameSequenceThreshold)
    }

    @Test("Two ways up one boulder come back as two groups")
    func splitsSequences() {
        let a = Fixture.sPath()
        let noisy = a.map { CGPoint(x: Double($0.x) + 0.003, y: Double($0.y) - 0.002) }
        let straight = (0..<60).map { CGPoint(x: 0.5, y: 0.9 - Double($0) / 59 * 0.7) }

        let clusters = BetaClustering.cluster([
            Fixture.climb(path: a, entropy: 1.40),
            Fixture.climb(path: noisy, entropy: 1.22),
            Fixture.climb(path: straight, entropy: 1.05)
        ])
        #expect(clusters.count == 2)
        // Cheapest group first.
        #expect((clusters.first?.meanEntropy ?? 9) < (clusters.last?.meanEntropy ?? 0))
    }

    @Test("Clips that could not be tracked never reach the comparison")
    func dropsUntrusted() {
        let bad = Fixture.climb(path: Fixture.sPath(), entropy: 1.1, confidence: 0.2)
        #expect(BetaClustering.cluster([bad]).isEmpty)
    }
}

// MARK: - Focus

@Suite("Focus")
struct FocusTests {

    private func bentArmClimbs(elbow: Double = 120, count: Int = 4) -> [Climb] {
        (0..<count).map {
            Fixture.climb(path: Fixture.sPath(), entropy: 1.3, kind: .bentArms,
                          elbow: elbow, daysAgo: Double(count - $0))
        }
    }

    @Test("The focus is the leak that keeps coming up")
    func picksRecurring() {
        #expect(FocusEngine.suggest(from: bentArmClimbs()) == .bentArms)
    }

    @Test("A focus starts from a measured baseline")
    func baseline() {
        let focus = FocusEngine.evaluate(existing: nil, climbs: bentArmClimbs())
        #expect(focus?.kind == .bentArms)
        #expect(abs((focus?.baseline ?? 0) - 120) < 0.5)
    }

    @Test("One climb is not a trend")
    func refusesSingleClimb() {
        // A partner who draws conclusions from one burn is not worth listening to.
        #expect(FocusEngine.evaluate(existing: nil, climbs: [bentArmClimbs()[0]]) == nil)
    }

    @Test("A focus retires itself once the target is met")
    func resolves() {
        let started = FocusEngine.evaluate(existing: nil, climbs: bentArmClimbs())
        let improved = bentArmClimbs(elbow: 165, count: 3)
        #expect(FocusEngine.evaluate(existing: started, climbs: improved)?.isResolved == true)
    }

    @Test("A focus stays open on small gains")
    func staysOpen() {
        let started = FocusEngine.evaluate(existing: nil, climbs: bentArmClimbs())
        let barely = bentArmClimbs(elbow: 126, count: 3)
        #expect(FocusEngine.evaluate(existing: started, climbs: barely)?.isResolved != true)
    }

    @Test("Progress is clamped to nothing and everything")
    func progressClamped() {
        var f = Focus(kind: .bentArms, startedAt: Date(), baseline: 120, latest: 179)
        #expect(f.progress > 0.99 && f.progress <= 1.0)
        f.latest = 100
        #expect(f.progress == 0)
    }

    @Test("Every leak has a metric, a target and a readable label")
    func everyLeakSupported() {
        let m = Fixture.metrics(offset: 0.75, deadpoints: [0.3])
        for kind in [LeakKind.bentArms, .weightOnArms, .lurchy, .impreciseFeet,
                     .hesitation, .wandering, .mistimedDynamics] {
            let value = FocusEngine.value(for: kind, in: m)
            #expect(value.isFinite, "\(kind.rawValue) has no metric")
            #expect(FocusEngine.target(for: kind, baseline: value).isFinite)
            #expect(!FocusEngine.format(kind: kind, value: value).isEmpty)
            #expect(!FocusEngine.meaning(for: kind).isEmpty)
        }
    }
}

// MARK: - Storage compatibility

@Suite("Storage")
struct StorageTests {

    @Test("Climbs saved before a metric existed still load")
    func legacyDecoding() throws {
        // Swift's synthesised decoder ignores property defaults, so adding a field
        // would otherwise wipe a climber's history on upgrade.
        let legacy = """
        {"entropy":1.2,"logJerk":9.0,"pathRatio":1.3,"staticElbowAngle":130,
         "pauseCount":2,"pauseTotal":4.0,"footAdjustments":3,
         "comPath":[[0.5,0.9],[0.5,0.3]],"duration":20.0,"trackingConfidence":0.8}
        """
        let m = try JSONDecoder().decode(Metrics.self, from: Data(legacy.utf8))
        #expect(m.entropy == 1.2)
        #expect(m.comOffsetFromFeet == 0)
        #expect(m.deadpointOffsets.isEmpty)
    }

    @Test("A climb survives a round trip through JSON")
    func roundTrip() throws {
        let climb = Fixture.climb(path: Fixture.sPath(), entropy: 1.31, kind: .bentArms)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(Climb.self, from: encoder.encode(climb))
        #expect(restored.id == climb.id)
        #expect(restored.metrics.entropy == climb.metrics.entropy)
        #expect(restored.findings.first?.kind == .bentArms)
        #expect(restored.metrics.comPath.count == climb.metrics.comPath.count)
    }
}
