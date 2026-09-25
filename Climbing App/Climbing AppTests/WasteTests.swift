import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Finding the movement that went nowhere, and the moments it happened.
@Suite("Wasted movement")
struct WasteTests {

    /// A body whose torso is 0.20, so 0.20 in these coordinates is one torso.
    private func at(_ t: Double, _ x: Double, _ y: Double) -> PoseFrame {
        Fixture.body(t: t, comY: y, feetX: x, wrist: CGPoint(x: x, y: y - 0.3))
    }

    @Test func aStraightClimbWastesNothing() {
        let frames = (0..<90).map { i in
            at(Double(i) / 30, 0.5, 0.85 - Double(i) * 0.006)
        }
        guard let r = WasteEngine.read(frames: frames) else {
            Issue.record("no reading"); return
        }
        #expect(r.isEmpty)
        #expect(r.wasted == 0)
        #expect(WasteEngine.summary(r) == nil)
    }

    @Test func aReachAndATakeBackIsARoundTrip() {
        // Up the wall, then one excursion out to the side and back, then on.
        var frames: [PoseFrame] = []
        var t = 0.0
        for i in 0..<30 { frames.append(at(t + Double(i) / 30, 0.5, 0.85 - Double(i) * 0.004)) }
        t = 1.0
        let y = 0.73
        // Out 0.2 (one torso) and back, over a second.
        for i in 0..<15 { frames.append(at(t + Double(i) / 30, 0.5 + Double(i) * 0.0133, y)) }
        for i in 0..<15 { frames.append(at(t + 0.5 + Double(i) / 30, 0.7 - Double(i) * 0.0133, y)) }
        t = 2.0
        for i in 0..<30 { frames.append(at(t + Double(i) / 30, 0.5, y - Double(i) * 0.004)) }

        guard let r = WasteEngine.read(frames: frames) else {
            Issue.record("no reading"); return
        }
        #expect(r.excursions.count == 1)
        guard let trip = r.worst else { Issue.record("no excursion"); return }
        // One torso length out and one back. The reported travel starts where
        // the body left the return neighborhood rather than where the detector
        // began watching, so it comes in a little under the full two and must
        // never come in over it.
        #expect(trip.travel > 1.3)
        #expect(trip.travel <= 2.1)
        #expect(abs(trip.start - 1.0) < 0.2)
        #expect(WasteEngine.summary(r) != nil)
    }

    /// Tracker jitter is not a round trip.
    @Test func jitterIsNotWaste() {
        let frames = (0..<120).map { i -> PoseFrame in
            let wobble = (i % 2 == 0 ? 1.0 : -1.0) * 0.004
            return at(Double(i) / 30, 0.5 + wobble, 0.6)
        }
        #expect(WasteEngine.read(frames: frames)?.isEmpty == true)
    }

    /// Standing still costs forearms, not distance, and is somebody else's
    /// finding. It must not show up here as waste.
    @Test func standingStillIsNotWaste() {
        let frames = (0..<150).map { at(Double($0) / 30, 0.5, 0.6) }
        #expect(WasteEngine.read(frames: frames)?.isEmpty == true)
    }

    /// The share is against everything traveled, so it cannot exceed one.
    @Test func theShareIsAFraction() {
        var frames: [PoseFrame] = []
        for lap in 0..<3 {
            let base = Double(lap) * 2.0
            for i in 0..<30 { frames.append(at(base + Double(i) / 30, 0.4 + Double(i) * 0.0067, 0.6)) }
            for i in 0..<30 { frames.append(at(base + 1.0 + Double(i) / 30, 0.6 - Double(i) * 0.0067, 0.6)) }
        }
        guard let r = WasteEngine.read(frames: frames) else {
            Issue.record("no reading"); return
        }
        #expect(!r.isEmpty)
        #expect(r.share > 0.5)
        #expect(r.share <= 1.0)
    }

    /// One long climb must not collapse into a single enormous round trip.
    @Test func anExcursionIsCappedInTime() {
        var frames: [PoseFrame] = []
        // Twenty seconds out and back: longer than the cap either way.
        for i in 0..<300 { frames.append(at(Double(i) / 30, 0.3 + Double(i) * 0.0013, 0.6)) }
        for i in 0..<300 { frames.append(at(10.0 + Double(i) / 30, 0.7 - Double(i) * 0.0013, 0.6)) }
        guard let r = WasteEngine.read(frames: frames) else {
            Issue.record("no reading"); return
        }
        #expect(r.excursions.allSatisfy { $0.duration <= WasteEngine.maximumSeconds + 0.1 })
    }

    @Test func tooFewFramesSaysNothing() {
        #expect(WasteEngine.read(frames: []) == nil)
        #expect(WasteEngine.read(frames: [at(0, 0.5, 0.5)]) == nil)
    }

    /// The caveat is the sentence that stops this reading as an accusation.
    @Test func theCaveatSaysARoundTripIsNotAlwaysWrong() {
        #expect(WasteEngine.caveat.lowercased().contains("not necessarily a mistake"))
    }
}
