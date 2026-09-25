import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Topped or fell, from the path of the center of mass alone.
///
/// Every fixture here is built from geometry, so the right answer is known
/// without running the detector first. The torso in `Fixture.body` is 0.20, so
/// a distance of 0.20 in these coordinates is one torso length.
@Suite("How a climb ended")
struct OutcomeTests {

    /// Up the wall at a steady rate, then still at the top for a second.
    private func ascent(rise: Double, thenHold seconds: Double,
                        climbSeconds: Double = 3.0) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        let rate = 1.0 / 30.0
        let climbing = Int(climbSeconds / rate)
        for i in 0..<climbing {
            let t = Double(i) * rate
            let y = 0.80 - rise * (Double(i) / Double(climbing))
            frames.append(Fixture.body(t: t, comY: y, feetX: 0.5,
                                       wrist: CGPoint(x: 0.5, y: y - 0.3)))
        }
        let holding = Int(seconds / rate)
        let top = 0.80 - rise
        for i in 0..<holding {
            let t = climbSeconds + Double(i) * rate
            frames.append(Fixture.body(t: t, comY: top, feetX: 0.5,
                                       wrist: CGPoint(x: 0.5, y: top - 0.3)))
        }
        return frames
    }

    @Test func holdingTheHighPointIsATop() {
        // 0.5 in coordinates is 2.5 torso lengths of rise, held for a second.
        let outcome = OutcomeEngine.outcome(frames: ascent(rise: 0.5, thenHold: 1.0))
        guard case .topped(let at) = outcome else {
            Issue.record("expected a top, got \(outcome)"); return
        }
        #expect(abs(at - 3.0) < 0.1)
    }

    @Test func droppingOffTheHighPointIsAFall() {
        var frames = ascent(rise: 0.5, thenHold: 0, climbSeconds: 3.0)
        // Free fall for half a second. The fixture's torso is 0.20 units, and a
        // real torso is about half a meter, so one unit is 2.5 m of wall and a
        // meter of fall is 0.4 units. Half a second of g is 1.23 m, which is
        // 2.45 torso lengths: comfortably past the 1.1 the detector asks for,
        // and the detector wants the whole window because a real fall runs it.
        let rate = 1.0 / 30.0
        let top = 0.80 - 0.5
        for i in 1...15 {
            let t = 3.0 + Double(i) * rate
            let fallen = 0.5 * 9.80665 * pow(Double(i) * rate, 2) * 0.4   // 0.4 units per meter
            frames.append(Fixture.body(t: t, comY: top + fallen, feetX: 0.5,
                                       wrist: CGPoint(x: 0.5, y: top + fallen - 0.3)))
        }
        let outcome = OutcomeEngine.outcome(frames: frames)
        guard case .fell(let at, let rise) = outcome else {
            Issue.record("expected a fall, got \(outcome)"); return
        }
        #expect(abs(at - 3.0) < 0.2)
        #expect(rise > 2.0)   // half the frame height, over a 0.20 torso
    }

    @Test func aControlledDownclimbIsNotAFall() {
        // Topped, held, then climbed back down over three seconds. The descent
        // is real but nothing like g, and it starts long after the high point.
        var frames = ascent(rise: 0.5, thenHold: 0.8)
        let rate = 1.0 / 30.0
        let top = 0.80 - 0.5
        let start = frames.last!.time
        for i in 1...90 {
            let t = start + Double(i) * rate
            let y = top + 0.5 * (Double(i) / 90.0)
            frames.append(Fixture.body(t: t, comY: y, feetX: 0.5,
                                       wrist: CGPoint(x: 0.5, y: y - 0.3)))
        }
        guard case .topped = OutcomeEngine.outcome(frames: frames) else {
            Issue.record("a downclimb after a hold is still a top"); return
        }
    }

    @Test func aTraverseIsNeither() {
        // Sideways, no rise. Neither reading applies and the detector must not
        // pick one anyway.
        let frames = (0..<120).map { i -> PoseFrame in
            let t = Double(i) / 30
            let x = 0.3 + 0.4 * (Double(i) / 120.0)
            return Fixture.body(t: t, comY: 0.5, feetX: x,
                                wrist: CGPoint(x: x, y: 0.2))
        }
        #expect(OutcomeEngine.outcome(frames: frames) == .unclear)
    }

    @Test func tooFewFramesSaysNothing() {
        #expect(OutcomeEngine.outcome(frames: []) == .unclear)
        #expect(OutcomeEngine.outcome(frames: Array(ascent(rise: 0.5, thenHold: 1).prefix(4)))
                == .unclear)
    }

    /// The cause of a fall is a finding that was already open, never a new one.
    @Test func theCauseIsAFindingThatWasAlreadyOpen() {
        let outcome = OutcomeEngine.Outcome.fell(at: 10.0, rise: 3.0)
        let early = Finding(kind: .bentArms, severity: .dominant, start: 0.5, end: 2.0,
                            message: "early and over by then")
        let during = Finding(kind: .weightOnArms, severity: .moderate, start: 8.0, end: 10.5,
                             message: "still open when it happened")
        #expect(OutcomeEngine.cause(of: outcome, findings: [early, during])?.kind == .weightOnArms)
        #expect(OutcomeEngine.cause(of: outcome, findings: [early]) == nil)
    }

    @Test func aTopHasNoCause() {
        let finding = Finding(kind: .bentArms, severity: .costly, start: 0, end: 99, message: "")
        #expect(OutcomeEngine.cause(of: .topped(at: 4), findings: [finding]) == nil)
    }
}
