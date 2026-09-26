import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Smoothness, and the rest that used to make a climb look jerky.
///
/// Log dimensionless jerk multiplies the jerk integral by the fifth power of
/// the duration and divides by the square of the path length. A rest adds
/// duration and no length. So the same movement, with a pause dropped into the
/// middle of it, scored as dramatically rougher, and Trace raised two findings
/// off one behaviour: start-stop movement because the number was high, and
/// reading the route while hanging on it because of the rest that made it high.
///
/// The measure was built for one discrete movement. A boulder is a series of
/// them with rests between, so it is now applied to each moving span and the
/// middle value taken.
@Suite("Smoothness and rests")
struct JerkTests {

    private func ease(_ u: Double) -> Double { 0.5 - 0.5 * cos(u * .pi) }

    /// A climb of five moves, optionally with a long rest in the middle of it.
    /// The movement either side of the rest is identical in both versions.
    private func climb(restSeconds: Double) -> [PoseFrame] {
        var points: [CGPoint] = []
        var times: [Double] = []
        var t = 0.0
        let step = 1.0 / 30.0
        var here = CGPoint(x: 0.5, y: 0.88)

        func move(to target: CGPoint) {
            let frames = 18
            for i in 1...frames {
                let e = ease(Double(i) / Double(frames))
                points.append(CGPoint(x: here.x + (target.x - here.x) * e,
                                      y: here.y + (target.y - here.y) * e))
                times.append(t); t += step
            }
            here = target
        }
        func rest(_ seconds: Double) {
            guard seconds > 0 else { return }
            for _ in 0..<Int(seconds / step) { points.append(here); times.append(t); t += step }
        }

        points.append(here); times.append(t); t += step
        move(to: CGPoint(x: 0.44, y: 0.72))
        move(to: CGPoint(x: 0.56, y: 0.58))
        rest(restSeconds)
        move(to: CGPoint(x: 0.46, y: 0.44))
        move(to: CGPoint(x: 0.55, y: 0.30))
        move(to: CGPoint(x: 0.50, y: 0.16))

        return zip(points, times).map { p, time in
            Fixture.body(t: time, comY: p.y, feetX: p.x,
                         wrist: CGPoint(x: p.x, y: p.y - 0.3))
        }
    }

    /// The headline, and the defect stated as a number. The old measure calls
    /// the resting climb far rougher; the new one knows it is the same climbing
    /// with a rest in it.
    @Test("A rest does not make the climbing rougher")
    func aRestIsNotRoughness() throws {
        let straight = climb(restSeconds: 0)
        let resting = climb(restSeconds: 3)

        let a = try #require(MetricsEngine.movingJerk(frames: straight))
        let b = try #require(MetricsEngine.movingJerk(frames: resting))
        #expect(abs(a - b) < 0.6, "per move, the rest moved smoothness from \(a) to \(b)")

        // And the measure this replaced, on the same two clips, so the gap is
        // stated rather than asserted.
        func whole(_ f: [PoseFrame]) -> Double {
            let path = f.compactMap { $0.com }
            return MetricsEngine.logDimensionlessJerk(
                path: path, times: f.map(\.time), length: MetricsEngine.pathLength(path))
        }
        let old = whole(resting) - whole(straight)
        #expect(old > 1.5,
                "the old measure only moved by \(old), so this proves nothing")
    }

    /// Too few moves to read is not a perfectly smooth climb.
    @Test("A clip with no moving in it has no smoothness")
    func tooFewMovesIsNil() {
        let still = (0..<40).map {
            Fixture.body(t: Double($0) / 30, comY: 0.5, feetX: 0.5,
                         wrist: CGPoint(x: 0.5, y: 0.2))
        }
        #expect(MetricsEngine.movingJerk(frames: still) == nil)
    }

    /// A climb measured the old way takes no part in the new comparison. Mixing
    /// the two is the mistake the field exists to stop.
    @Test("A climb with no per-move reading is not judged on smoothness")
    func oldClimbsAreNotJudged() {
        var m = Fixture.metrics(path: Fixture.sPath(), entropy: 1.2)
        m.movingJerk = nil
        let history = [12.0, 12.5, 13.0, 12.2]
        #expect(!FindingEngine.findings(from: m, frames: [], priorJerk: history)
                    .contains { $0.kind == .lurchy })

        m.movingJerk = 18
        #expect(FindingEngine.findings(from: m, frames: [], priorJerk: history)
                    .contains { $0.kind == .lurchy })
    }
}
