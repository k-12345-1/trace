import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

private final class BundleToken {}

/// The analysis, on an actual climber.
///
/// Every other test in this suite runs against a synthetic climber, and a
/// synthetic climber is drawn by the same assumptions the analysis is built on:
/// the center of mass rises smoothly because the generator moved it smoothly,
/// the arms are straight because they were drawn straight, and there is no
/// tracker noise because there is no tracker. Agreeing with that fixture proves
/// the arithmetic, not the measurement.
///
/// This fixture is a real 30-second ascent of a V2, filmed from the floor of a
/// gym on a phone at 60fps, run through `PoseTracker` and saved as the frames it
/// produced. 1718 frames, 98% of them tracked. It is pose data rather than
/// video so the repository does not carry 70MB of someone's climb, and it is
/// the exact output the app would have had from that clip.
///
/// Two things were wrong when it was first run, both of the same kind: a
/// constant that is not a length being used as one.
///
/// The climber was told 68% of their height had been gained twice, on an ascent
/// where they never dropped more than a quarter of a torso length. And 28% of
/// the climb was counted as standing still, on a clip where they stop once.
///
/// What is still open is the judgement rather than the measurement: this climb
/// grades "Mixed", and a climber watching it calls it efficient. The three
/// components holding it there are the elbow angle, the round trips and the
/// travel between moves, and each is an absolute threshold that has never been
/// checked against more than this one clip. Calibrating them needs a handful of
/// clips with a verdict attached, not a number moved until this one passes.
@Suite("A real climb")
struct RealClimbTests {

    private func frames() throws -> [PoseFrame] {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "realclimb", withExtension: "json"),
                               "the tracked climb is missing from the test bundle")
        return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
    }

    // MARK: It is what it says it is

    @Test("The fixture is a tracked ascent")
    func theFixtureIsWhatItClaims() throws {
        let clip = try frames()
        #expect(clip.count > 1500)
        let tracked = clip.filter { $0.com != nil }
        #expect(Double(tracked.count) / Double(clip.count) > 0.95)

        let m = MetricsEngine.compute(frames: clip)
        #expect(m.isTrustworthy)
        #expect(m.duration > 25)

        // It goes up: the center of mass ends higher than it started, by several
        // torso lengths. (y grows downward.)
        let torso = try #require(MetricsEngine.medianTorso(tracked))
        let ys = m.comPath.map { Double($0.y) }
        #expect((ys.max()! - ys.min()!) / torso > 4)
    }

    // MARK: Re-lifting

    /// The one that made the app call a clean ascent very inefficient.
    ///
    /// `gross` was the sum of every frame-to-frame upward step, so it summed
    /// the upward half of the tracker's jitter across seventeen hundred frames.
    /// This asserts both halves: that the measure now reports what happened,
    /// and that the old one did not, on the very same frames.
    @Test("A climber who never dropped is not told they re-lifted")
    func reLiftingIsNotTrackerNoise() throws {
        let clip = try frames()
        let m = MetricsEngine.compute(frames: clip)
        let torso = try #require(MetricsEngine.medianTorso(clip))

        let lift = try #require(BodyScale.lift(path: m.comPath, torso: torso))
        #expect(lift.ratio < 1.05, "ratio was \(lift.ratio)")

        // The old measure, on the same path.
        let ys = m.comPath.map { Double($0.y) }
        let summedSteps = (1..<ys.count).reduce(0.0) { $0 + max(0, ys[$1 - 1] - ys[$1]) }
        let net = ys.max()! - ys.min()!
        #expect(summedSteps / net > 1.5,
                "the old measure read \(summedSteps / net), so this proves nothing")
    }

    /// And it still catches a real one. The same climb with a drop spliced into
    /// the middle of it: down a torso length and a half, then back up.
    @Test("A real drop is still counted")
    func arealDropIsStillCounted() throws {
        let clip = try frames()
        let m = MetricsEngine.compute(frames: clip)
        let torso = try #require(MetricsEngine.medianTorso(clip))

        var path = m.comPath
        let middle = path.count / 2
        let drop = torso * 1.5
        let down = (1...40).map { i in
            CGPoint(x: path[middle].x,
                    y: path[middle].y + drop * Double(i) / 40)
        }
        path.insert(contentsOf: down + down.reversed(), at: middle)

        let lift = try #require(BodyScale.lift(path: path, torso: torso))
        #expect(lift.ratio > 1.2, "a torso and a half of lost height went unnoticed: \(lift.ratio)")
    }

    // MARK: Standing still

    /// Stillness was an absolute speed in image units, and an image unit is a
    /// fraction of the frame rather than a length. This climber is small in
    /// frame, so the old threshold called more than a quarter of their ascent
    /// "still" and then measured their elbows and their balance during it.
    @Test("Stillness is measured against the body, not the frame")
    func stillnessIsBodyRelative() throws {
        let clip = try frames()
        let tracked = clip.filter { $0.meanConfidence > 0 && $0.com != nil }
        let torso = try #require(MetricsEngine.medianTorso(tracked))
        let speeds = MetricsEngine.speedSeries(path: tracked.compactMap { $0.com },
                                               times: tracked.map(\.time))

        func share(below cutoff: Double) -> Double {
            Double(speeds.filter { $0 < cutoff }.count) / Double(speeds.count)
        }

        let now = share(below: MetricsEngine.stillSpeed(torso: torso))
        let before = share(below: MetricsEngine.stillSpeedWithoutABody)
        #expect(now < 0.16, "still \(now) of the climb")
        #expect(before > 0.24, "the old threshold read \(before), so this proves nothing")

        // This climber is filmed small, so the old constant was loose on them.
        // A climber filling the frame would have had it the other way round, and
        // that is the point: it was never the same test twice.
        #expect(torso < 0.15)
    }

    /// The pauses that survive are the ones a person watching would name.
    @Test("A climb with one hesitation in it does not read as a rest every few seconds")
    func pausesAreNotEverywhere() throws {
        let clip = try frames()
        let m = MetricsEngine.compute(frames: clip)
        #expect(m.pauseTotal / m.duration < 0.05, "\(m.pauseTotal)s of \(m.duration)s")
    }

    // MARK: The whole pipeline

    @Test("The clip grades, and names what it graded")
    func itProducesAReadableVerdict() throws {
        let clip = try frames()
        let m = MetricsEngine.compute(frames: clip)
        let climb = Climb(recordedAt: Date(), videoFilename: "realclimb.mp4",
                          label: "V2", metrics: m,
                          findings: FindingEngine.findings(from: m,
                                                           frames: MetricsEngine.ascent(clip),
                                                           priorJerk: []),
                          frames: clip, sent: nil, gymID: nil)

        let reading = try #require(EfficiencyEngine.read(climb))
        #expect(!reading.components.isEmpty)
        // Every component has to say what it measured, in a sentence that reads.
        for c in reading.components {
            #expect(!c.detail.isEmpty)
            #expect(!c.detail.contains("-"), "\(c.name) says \(c.detail)")
        }
        // Re-lifting is no longer what the grade is about.
        let lift = reading.components.first { $0.name == "Re-lifting" }
        #expect((lift?.contribution ?? 0) < 0.01)
    }
}
