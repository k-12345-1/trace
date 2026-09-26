import Testing
import Foundation
@testable import ClimbingApp

private final class BundleToken {}

/// Whether the phone stayed put.
///
/// Every spatial measurement in Trace is computed from where the body went
/// inside the frame, and all of them assume the frame is a fixed window onto
/// the wall. Nothing checked it, and the footage people will most naturally
/// import is the kind that breaks it: somebody following you up the wall.
///
/// On the four real clips available, the one filmed from the floor moved the
/// picture 0.01 frame heights over thirty seconds. The three handheld ones moved
/// it 1.74, 1.87 and 2.96. The second of those is a climber who went up a whole
/// wall, and Trace graded her "very inefficient, 82% wasted", 78 points of which
/// were "your height was gained twice" as the operator bobbed.
@Suite("Camera motion")
struct CameraMotionTests {

    /// A still clip, registered against itself.
    ///
    /// The fixture is three seconds of a real climb filmed from the floor, which
    /// is the only footage in the repository and the only kind Trace asks for.
    @Test("A phone on the floor reads as still")
    func aStillPhoneReadsAsStill() async throws {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "climber", withExtension: "mp4"))
        let reading = try #require(await CameraMotion.read(url: url))

        #expect(reading.confidence > 0.8, "registered only \(reading.confidence)")
        #expect(reading.travel < CameraMotion.staticTravel,
                "travelled \(reading.travel) frame heights")
        #expect(reading.isStatic)
    }

    /// The threshold sits clear of both sides rather than splitting them.
    @Test("The threshold is not a split difference")
    func theThresholdHasRoomEitherSide() {
        // Measured: still 0.01, handheld 1.74, 1.87, 2.96.
        #expect(CameraMotion.staticTravel > 0.01 * 10)
        #expect(CameraMotion.staticTravel < 1.74 / 4)
    }

    /// A reading with too few registered pairs says nothing rather than "still".
    @Test("Unregistrable footage is not called still")
    func lowConfidenceIsNotStill() {
        let unsure = CameraMotion.Reading(travel: 0.001, drift: 0, confidence: 0.2)
        #expect(!unsure.isStatic)
        let sure = CameraMotion.Reading(travel: 0.001, drift: 0, confidence: 0.99)
        #expect(sure.isStatic)
    }

    // MARK: What the climb does with it

    @Test("A climb remembers whether the phone moved")
    func theClimbRemembers() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        #expect(climb.cameraWasStill == nil, "unknown is not the same as still")

        climb.cameraTravel = 0.01
        #expect(climb.cameraWasStill == true)

        climb.cameraTravel = 1.74
        #expect(climb.cameraWasStill == false)
    }

    /// A climb recorded before any of this existed decodes, and says it does not
    /// know rather than claiming the phone was still.
    @Test("An older climb decodes as unknown")
    func anOlderClimbDecodesAsUnknown() throws {
        let climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(try JSONSerialization.jsonObject(
            with: try encoder.encode(climb)) as? [String: Any])
        json.removeValue(forKey: "cameraTravel")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(Climb.self,
                                      from: try JSONSerialization.data(withJSONObject: json))
        #expect(back.cameraTravel == nil)
        #expect(back.cameraWasStill == nil)
    }

    // MARK: What the screen does with it

    /// A moving camera is shown as its own thing, not as "I could not see that
    /// one clearly", because Trace saw it perfectly.
    @Test("A moving camera is explained, not graded")
    func theScreenExplainsRatherThanGrades() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.cameraTravel = 1.74
        #expect(ResultsReadout.of(climb) == .cameraMoved)
    }

    @Test("A climb filmed from the floor is read as before")
    func aStillClimbIsUnaffected() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.cameraTravel = 0.01
        #expect(ResultsReadout.of(climb) == .measurements)
    }

    /// A climb from before any of this is read as before, rather than being
    /// withheld on a suspicion.
    @Test("An unknown camera is not treated as a moving one")
    func unknownIsNotMoving() {
        let climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        #expect(climb.cameraTravel == nil)
        #expect(ResultsReadout.of(climb) == .measurements)
    }

    /// The order is an argument, so it is asserted. A clip that is both filmed
    /// on a moving phone and badly tracked is reported as the first, because
    /// "I could not see you" is the wrong sentence when Trace saw it fine.
    @Test("A moving camera outranks poor tracking")
    func theCameraComesFirst() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.metrics.trackingConfidence = 0.1
        #expect(ResultsReadout.of(climb) == .unreadable)
        climb.cameraTravel = 2.0
        #expect(ResultsReadout.of(climb) == .cameraMoved)
    }


}
