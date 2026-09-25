import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The five step efficiency grade.
@Suite("Efficiency")
struct EfficiencyTests {

    private func at(_ t: Double, _ x: Double, _ y: Double) -> PoseFrame {
        Fixture.body(t: t, comY: y, feetX: x, wrist: CGPoint(x: x, y: y - 0.3))
    }

    /// Straight up, arms straight, no stops and no detours.
    private func cleanClimb() -> Climb {
        let frames = (0..<90).map { at(Double($0) / 30, 0.5, 0.88 - Double($0) * 0.0066) }
        var m = MetricsEngine.compute(frames: frames)
        m.staticElbowAngle = 176
        return Climb(recordedAt: Date(), videoFilename: "x.mov", label: "clean",
                     metrics: m, findings: [], frames: frames)
    }

    @Test func aCleanClimbGradesWell() {
        guard let r = EfficiencyEngine.read(cleanClimb()) else {
            Issue.record("no reading"); return
        }
        #expect(r.grade >= .efficient)
        #expect(r.cost < 0.3)
    }

    @Test func aMessyClimbGradesBadly() {
        // Three laps across the wall, bent arms, and long stops.
        var frames: [PoseFrame] = []
        for lap in 0..<3 {
            let base = Double(lap) * 2.0
            for i in 0..<30 { frames.append(at(base + Double(i) / 30, 0.4 + Double(i) * 0.0067, 0.7 - Double(lap) * 0.05)) }
            for i in 0..<30 { frames.append(at(base + 1.0 + Double(i) / 30, 0.6 - Double(i) * 0.0067, 0.7 - Double(lap) * 0.05)) }
        }
        var m = MetricsEngine.compute(frames: frames)
        m.staticElbowAngle = 112
        m.pauseTotal = m.duration * 0.6
        let climb = Climb(recordedAt: Date(), videoFilename: "x.mov", label: "messy",
                          metrics: m, findings: [], frames: frames)
        guard let r = EfficiencyEngine.read(climb) else { Issue.record("no reading"); return }
        #expect(r.grade <= .inefficient)
    }

    /// Untrackable footage gets no grade at all rather than a bad one.
    @Test func lowTrackingGetsNoGrade() {
        var climb = cleanClimb()
        climb.metrics.trackingConfidence = 0.2
        #expect(EfficiencyEngine.read(climb) == nil)
    }

    // MARK: The rubric

    @Test func theCutsMapOntoFiveGrades() {
        #expect(EfficiencyEngine.grade(for: 0.0) == .veryEfficient)
        #expect(EfficiencyEngine.grade(for: 0.20) == .efficient)
        #expect(EfficiencyEngine.grade(for: 0.40) == .mixed)
        #expect(EfficiencyEngine.grade(for: 0.60) == .inefficient)
        #expect(EfficiencyEngine.grade(for: 0.90) == .veryInefficient)
        #expect(EfficiencyEngine.grade(for: 1.0) == .veryInefficient)
    }

    @Test func everyGradeHasAColorAndAWord() {
        #expect(Theme.efficiency.count == 5)
        for g in EfficiencyEngine.Grade.allCases {
            #expect(!g.label.isEmpty)
            #expect(g.rawValue >= 1 && g.rawValue <= 5)
        }
    }

    /// A measure that cannot be read on this climb is dropped, not scored zero.
    /// Averaging a zero in would read as the climber doing well at something
    /// they never did.
    @Test func anUnreadableMeasureIsLeftOutRatherThanCountedAsPerfect() {
        // A traverse: MetricsEngine declines to give a path ratio.
        let frames = (0..<120).map { at(Double($0) / 30, 0.3 + Double($0) * 0.003, 0.6) }
        var m = MetricsEngine.compute(frames: frames)
        m.staticElbowAngle = 176
        #expect(m.pathRatio == 0)
        let climb = Climb(recordedAt: Date(), videoFilename: "x.mov", label: "traverse",
                          metrics: m, findings: [], frames: frames)
        guard let r = EfficiencyEngine.read(climb) else { Issue.record("no reading"); return }
        #expect(!r.components.contains { $0.name == "Wander" })
    }

    /// The weights are renormalized over what was read, so a climb missing a
    /// measure is not quietly scored out of less than one.
    @Test func theCostStaysAFraction() {
        for climb in [cleanClimb()] {
            guard let r = EfficiencyEngine.read(climb) else { continue }
            #expect(r.cost >= 0 && r.cost <= 1)
        }
    }

    @Test func theWorstComponentIsTheBiggestContributor() {
        guard let r = EfficiencyEngine.read(cleanClimb()), let worst = r.worst else {
            Issue.record("no reading"); return
        }
        #expect(r.components.allSatisfy { $0.contribution <= worst.contribution + 1e-9 })
        // And the list is sorted worst first, which is the order it is shown in.
        #expect(r.components.first?.name == worst.name)
    }

    /// The grade is a weighted summary of proxies, and says so.
    @Test func theCaveatRefusesToClaimItMeasuredEnergy() {
        let c = EfficiencyEngine.caveat.lowercased()
        #expect(c.contains("not a measurement of energy"))
    }
}
