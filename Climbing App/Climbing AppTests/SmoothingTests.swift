import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The same climb, filmed at two frame rates, has to measure the same.
///
/// It did not. The moving average that cleans the centre of mass before
/// anything is derived from it was five frames wide, which is sixty six
/// milliseconds at thirty frames a second and thirty three at sixty. A clip
/// shot at the higher rate therefore carried twice as much jitter into a third
/// derivative, and came out jerkier for no reason a climber could act on.
///
/// Trace films at sixty where the camera offers an unbinned format and thirty
/// where it does not, and an imported clip is whatever the phone recorded, so
/// one library holds both. Smoothness is only ever compared against the
/// climber's own earlier climbs, which is exactly the comparison this broke.
@Suite("Frame rate")
struct SmoothingTests {

    /// One climb, sampled at whatever rate is asked for, with a fixed jitter
    /// pattern on top so the two clips carry the same noise in the same places.
    private func climb(fps: Double, seconds: Double = 6) -> [PoseFrame] {
        let n = Int(seconds * fps)
        return (0..<n).map { i in
            let t = Double(i) / fps
            let u = t / seconds
            // A smooth rise with a little side to side, plus a deterministic
            // wobble that is a function of time, not of frame index, so both
            // rates see the same underlying signal.
            //
            // The wobble is kept well under the slower clip's Nyquist limit, at
            // about three and five hertz. Jitter above it is genuinely not in a
            // thirty frame clip, and a test that put it there would be asking
            // the two rates to agree about something only one of them can see.
            let jitter = sin(t * 20) * 0.0016 + sin(t * 33) * 0.0011
            let x = 0.5 + sin(u * .pi * 3) * 0.06 + jitter
            let y = 0.9 - u * 0.7 + jitter
            return Fixture.body(t: t, comY: y, feetX: x,
                                wrist: CGPoint(x: x, y: y - 0.3))
        }
    }

    private func jerk(_ frames: [PoseFrame]) -> Double {
        let smoothed = PoseTracker.smooth(frames)
        let path = smoothed.compactMap { $0.com }
        let times = smoothed.map(\.time)
        return MetricsEngine.logDimensionlessJerk(
            path: path, times: times, length: MetricsEngine.pathLength(path))
    }

    /// The headline. Sixty and thirty have to agree about the same movement.
    @Test("Smoothness does not depend on the frame rate")
    func smoothnessSurvivesTheFrameRate() {
        let slow = jerk(climb(fps: 30))
        let fast = jerk(climb(fps: 60))
        #expect(abs(slow - fast) < 0.5,
                "30 fps read \(slow) and 60 fps read \(fast) on the same climb")
    }

    /// And the window really is a duration: twice the rate, twice the taps.
    @Test("The window is a slice of time, not a count of frames")
    func theWindowIsInSeconds() {
        let thirty = PoseTracker.smooth(climb(fps: 30))
        let sixty = PoseTracker.smooth(climb(fps: 60))
        // Sample both at the same instants and compare what came out.
        var worst = 0.0
        for t in stride(from: 0.5, to: 5.5, by: 0.25) {
            guard let a = thirty.min(by: { abs($0.time - t) < abs($1.time - t) })?.com,
                  let b = sixty.min(by: { abs($0.time - t) < abs($1.time - t) })?.com
            else { continue }
            worst = max(worst, hypot(a.x - b.x, a.y - b.y))
        }
        #expect(worst < 0.004, "the two rates smoothed to paths \(worst) apart")
    }

    /// A clip whose timestamps say nothing useful still gets filtered rather
    /// than dividing by zero.
    @Test("A clip with no time between frames is still safe")
    func degenerateTimesAreSafe() {
        let frames = (0..<20).map { _ in
            Fixture.body(t: 0, comY: 0.5, feetX: 0.5, wrist: CGPoint(x: 0.5, y: 0.2))
        }
        #expect(PoseTracker.smooth(frames).count == frames.count)
    }
}
