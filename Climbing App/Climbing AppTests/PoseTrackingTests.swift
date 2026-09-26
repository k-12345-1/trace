import Testing
import Foundation
@testable import ClimbingApp

private final class BundleToken {}

/// Tracking a real video, in whatever is running these tests.
///
/// Everything else in the suite starts from pose frames: either drawn by a
/// fixture or, in `RealClimbTests`, tracked once on a Mac and saved. Nothing
/// asserted that the tracker itself works, and it turns out that where these
/// tests run, it does not.
///
/// `PoseTracker` reads every frame of this three-second clip on macOS and finds
/// a body in all 181 of them. The same code, the same file, in the iOS
/// Simulator finds a body in none. Frame extraction is fine: the Simulator
/// reads exactly the same number of frames. Vision's body-pose request simply
/// returns no observations there.
///
/// That is worth a test rather than a note, because it explains a thing that
/// looked like a bug in the app and is not: import any clip into Trace on a
/// Simulator and it says "I could not see that one clearly", every time,
/// however good the footage. It also means the app's central feature has never
/// been seen working anywhere except a command line tool, and will not be until
/// it is run on a phone.
@Suite("Pose tracking")
struct PoseTrackingTests {

    private var clip: URL {
        get throws {
            let bundle = Bundle(for: BundleToken.self)
            return try #require(bundle.url(forResource: "climber", withExtension: "mp4"),
                                "the climber clip is missing from the test bundle")
        }
    }

    /// The frames come out whatever the platform: this is the half that works.
    @Test("Every frame of the clip is read")
    func everyFrameIsRead() async throws {
        let frames = try await PoseTracker.track(url: try clip) { _ in }
        #expect(frames.count > 150, "read \(frames.count) frames")
    }

    /// And the half that does not.
    ///
    /// Written as a known issue rather than a skip, so that the day it starts
    /// working the suite says so by failing: a known issue that stops happening
    /// is reported, and then this test becomes a plain expectation.
    @Test("A body is found in the footage")
    func aBodyIsFound() async throws {
        let frames = try await PoseTracker.track(url: try clip) { _ in }
        let tracked = frames.filter { $0.com != nil }
        let share = Double(tracked.count) / Double(max(frames.count, 1))

        #if targetEnvironment(simulator)
        withKnownIssue("Vision finds no body in the iOS Simulator. The same clip, through the same code, tracks 181 of 181 frames on macOS.") {
            #expect(share > 0.8, "tracked \(tracked.count) of \(frames.count)")
        }
        #else
        #expect(share > 0.8, "tracked \(tracked.count) of \(frames.count)")
        #endif
    }
}
