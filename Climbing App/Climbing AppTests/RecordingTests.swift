import Testing
import Foundation
import AVFoundation
@testable import ClimbingApp

/// What happens to a recording that was stopped by something other than you.
///
/// A capture session is interrupted by ordinary life: a call arrives, Control
/// Center comes down, the screen locks with the phone on the floor at the
/// bottom of the wall. iOS stops the recording and hands back an error, and the
/// old code read every error as a loss: it threw the file away and closed the
/// screen. The file is usually complete, and AVFoundation says so in the error
/// itself.
@Suite("Recordings that end badly")
struct RecordingTests {

    private let url = URL(fileURLWithPath: "/tmp/climb.mov")

    @Test("A recording that ended cleanly is kept")
    func noErrorIsKept() {
        #expect(CameraController.ending(for: url, error: nil) == .keep(url))
    }

    /// The one that matters. This is the shape of the error iOS sends when it
    /// stopped the recording itself and the file is fine.
    @Test("An interruption that still wrote the file is kept")
    func aFinishedFileIsKept() {
        let error = NSError(domain: AVFoundationErrorDomain,
                            code: AVError.Code.deviceWasDisconnected.rawValue,
                            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true])
        #expect(CameraController.ending(for: url, error: error) == .keep(url))
    }

    @Test("A recording that wrote nothing is lost, and says why")
    func aTrulyFailedRecordingIsLost() {
        let error = NSError(domain: AVFoundationErrorDomain,
                            code: AVError.Code.diskFull.rawValue,
                            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false,
                                       NSLocalizedDescriptionKey: "There is no room left."])
        #expect(CameraController.ending(for: url, error: error)
                == .lost("There is no room left."))
    }

    /// An error with nothing in it is still a loss, not a crash and not a
    /// silently empty clip.
    @Test("An error that says nothing is still a loss")
    func aBareErrorIsLost() {
        let error = NSError(domain: "x", code: 1, userInfo: nil)
        if case .lost = CameraController.ending(for: url, error: error) {} else {
            Issue.record("a bare error was treated as a usable clip")
        }
    }
}
