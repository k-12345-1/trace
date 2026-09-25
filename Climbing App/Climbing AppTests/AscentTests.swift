import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The clip is not the climb.
///
/// Everything after the high point is topping out, downclimbing, or dropping
/// off, and none of it is climbing. These pin the trim and the things that were
/// wrong without it.
@Suite("Measuring the ascent")
struct AscentTests {

    private func at(_ t: Double, _ x: Double, _ y: Double) -> PoseFrame {
        Fixture.body(t: t, comY: y, feetX: x, wrist: CGPoint(x: x, y: y - 0.3))
    }

    /// Up the wall, then back down to where it started, which is what a clip of
    /// a boulder looks like when you keep filming.
    private func upAndDown() -> [PoseFrame] {
        var frames: [PoseFrame] = []
        for i in 0..<90 { frames.append(at(Double(i) / 30, 0.5, 0.88 - Double(i) * 0.0066)) }
        for i in 0..<90 { frames.append(at(3.0 + Double(i) / 30, 0.5, 0.29 + Double(i) * 0.0066)) }
        return frames
    }

    @Test func theTrimStopsAtTheHighPoint() {
        let all = upAndDown()
        let up = MetricsEngine.ascent(all)
        #expect(up.count < all.count)
        // The last upward frame is at 89/30, just under three seconds.
        // Within a tenth of a torso of the top counts as having got there, so
        // it can land a frame or two before the very last upward sample.
        #expect(abs((up.last?.time ?? 0) - 2.93) < 0.12)
    }

    /// The cut is the first frame to reach the top, not the single lowest
    /// sample, so one noisy frame cannot move it.
    @Test func oneNoisyFrameDoesNotMoveTheCut() {
        var frames = upAndDown()
        // One frame misplaced a third of a torso length above everything else,
        // a second into the descent. That is the shape of a tracker spike.
        let i = 120
        let spike = frames[i].com!
        frames[i] = Fixture.body(t: frames[i].time, comY: spike.y - 0.07,
                                 feetX: 0.5, wrist: CGPoint(x: 0.5, y: 0.1))
        let up = MetricsEngine.ascent(frames)
        #expect((up.last?.time ?? 99) < 3.2)
    }

    /// The defect this was written for: measured over the whole clip a boulder
    /// that finishes near where it started divides by nearly nothing, and the
    /// copy reports five hundred percent.
    @Test func comingBackDownNoLongerInflatesTheWanderingLine() {
        let whole = MetricsEngine.compute(frames: upAndDown())
        // The ascent is a dead straight line, so there is nothing to report.
        #expect(whole.pathRatio < 1.1)
    }

    /// And a climb that genuinely went nowhere still reports nothing rather
    /// than a large number.
    @Test func aTraverseReportsNoPathRatioAtAll() {
        let sideways = (0..<120).map { at(Double($0) / 30, 0.3 + Double($0) * 0.003, 0.6) }
        #expect(MetricsEngine.compute(frames: sideways).pathRatio == 0)
    }

    @Test func theGuardIsInTorsoLengths() {
        // A climb of exactly four torso lengths, straight up. The torso in the
        // fixture is 0.20, so that is 0.8 in image units.
        let up = (0..<90).map { at(Double($0) / 30, 0.5, 0.88 - Double($0) * 0.009) }
        let m = MetricsEngine.compute(frames: up)
        #expect(m.pathRatio > 0)
        #expect(m.pathRatio < 1.1)
    }

    /// Dropping off the top is a round trip the size of the route. It must not
    /// be reported as wasted movement.
    @Test func theDescentIsNotWastedMovement() {
        let whole = WasteEngine.read(frames: upAndDown())
        let climbing = WasteEngine.read(frames: MetricsEngine.ascent(upAndDown()))
        #expect(whole?.isEmpty == false)      // over the whole clip it looks like waste
        #expect(climbing?.isEmpty == true)    // over the ascent there is none
    }

    /// The outcome is read over the whole clip on purpose: the fall happens
    /// after the high point, so trimming to the ascent would hide every one.
    @Test func theOutcomeStillSeesTheWholeClip() {
        var frames = (0..<90).map { at(Double($0) / 30, 0.5, 0.88 - Double($0) * 0.0066) }
        let top = 0.88 - 89 * 0.0066
        for i in 1...15 {
            let t = 3.0 + Double(i) / 30
            let fallen = 0.5 * 9.80665 * pow(Double(i) / 30, 2) * 0.4
            frames.append(at(t, 0.5, top + fallen))
        }
        guard case .fell = OutcomeEngine.outcome(frames: frames) else {
            Issue.record("the fall was trimmed away"); return
        }
    }

    /// Trips a fraction of a second apart are one trip listed twice.
    @Test func closeTripsMerge() {
        let trips = [WasteEngine.Excursion(start: 1.0, end: 2.0, travel: 1.5),
                     WasteEngine.Excursion(start: 2.3, end: 3.0, travel: 1.0),
                     WasteEngine.Excursion(start: 9.0, end: 10.0, travel: 2.0)]
        let merged = WasteEngine.merge(trips)
        #expect(merged.count == 2)
        #expect(merged[0].start == 1.0)
        #expect(merged[0].end == 3.0)
        #expect(merged[0].travel == 2.5)
    }

    @Test func distantTripsDoNot() {
        let trips = [WasteEngine.Excursion(start: 1.0, end: 2.0, travel: 1.5),
                     WasteEngine.Excursion(start: 5.0, end: 6.0, travel: 1.0)]
        #expect(WasteEngine.merge(trips).count == 2)
    }

    /// A clip with nothing in it must not be trimmed to nothing.
    @Test func theTrimNeverEmptiesTheClip() {
        let tiny = (0..<3).map { at(Double($0) / 30, 0.5, 0.5) }
        #expect(MetricsEngine.ascent(tiny).count == tiny.count)
        #expect(MetricsEngine.ascent([]).isEmpty)
    }
}
