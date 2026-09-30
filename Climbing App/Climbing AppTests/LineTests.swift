import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Reading a line through scanned holds, and knowing what it cannot say.
@Suite("The line through a route")
struct LineTests {

    private func hold(_ x: Double, _ y: Double, size: Double = 0.04) -> CGRect {
        CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// Origin is top left, so a bigger y is lower on the wall.
    @Test func itStartsAtTheBottomAndWorksUp() {
        let holds = [hold(0.5, 0.2), hold(0.5, 0.9), hold(0.5, 0.5)]
        let line = LineEngine.read(holds: holds)
        let ys = line?.holds.map(\.midY) ?? []
        #expect(ys == ys.sorted(by: >))
        #expect(abs((ys.first ?? 0) - 0.9) < 0.001)
    }

    @Test func itNeverGoesBackDown() {
        // A weave, so a naive nearest-neighbor walk could double back.
        let holds = [hold(0.2, 0.9), hold(0.8, 0.8), hold(0.25, 0.6),
                     hold(0.75, 0.45), hold(0.3, 0.25), hold(0.5, 0.1)]
        guard let line = LineEngine.read(holds: holds) else {
            Issue.record("no line"); return
        }
        let ys = line.holds.map(\.midY)
        for (a, b) in zip(ys, ys.dropFirst()) {
            #expect(b <= a, "the line dropped from \(a) to \(b)")
        }
        #expect(line.holds.count == holds.count)
    }

    @Test func twoHoldsIsNotALine() {
        #expect(LineEngine.read(holds: [hold(0.5, 0.9), hold(0.5, 0.4)]) == nil)
        #expect(LineEngine.read(holds: []) == nil)
    }

    // MARK: What stands out

    @Test func oneBigGapIsTheLongMove() {
        // Four evenly spaced, then a jump twice as far.
        let holds = [hold(0.5, 0.90), hold(0.5, 0.80), hold(0.5, 0.70),
                     hold(0.5, 0.60), hold(0.5, 0.30)]
        guard let line = LineEngine.read(holds: holds) else {
            Issue.record("no line"); return
        }
        #expect(line.moves.filter { $0.kind == .long }.count == 1)
        #expect(line.longest?.index == 3)
        #expect((line.longest?.reach ?? 0) > 2.5)
    }

    @Test func evenSpacingHasNoLongMove() {
        let holds = (0..<6).map { hold(0.5, 0.9 - Double($0) * 0.12) }
        guard let line = LineEngine.read(holds: holds) else {
            Issue.record("no line"); return
        }
        #expect(line.moves.allSatisfy { $0.kind == .ordinary })
        #expect(LineEngine.note(for: line.moves[0]) == nil)
    }

    @Test func holdsSideBySideReadAsAcross() {
        // Barely any rise, a lot of travel.
        let holds = [hold(0.15, 0.62), hold(0.40, 0.60),
                     hold(0.65, 0.58), hold(0.90, 0.56)]
        guard let line = LineEngine.read(holds: holds) else {
            Issue.record("no line"); return
        }
        #expect(line.moves.allSatisfy { $0.kind == .across })
        #expect(line.isTraverse)
    }

    @Test func aStraightLadderIsNotATraverse() {
        let holds = (0..<6).map { hold(0.5, 0.9 - Double($0) * 0.13) }
        #expect(LineEngine.read(holds: holds)?.isTraverse == false)
    }

    @Test func twoHoldsAlmostTouchingReadAsAMatch() {
        let holds = [hold(0.5, 0.90), hold(0.5, 0.70), hold(0.52, 0.69),
                     hold(0.5, 0.50), hold(0.5, 0.30)]
        guard let line = LineEngine.read(holds: holds) else {
            Issue.record("no line"); return
        }
        #expect(line.moves.contains { $0.kind == .match })
    }

    // MARK: What it is careful not to say

    /// Everything is a ratio against this route's own median gap. Scaling the
    /// whole route, which is what moving the camera does, must change nothing.
    @Test func movingTheCameraChangesNothing() {
        let holds = [hold(0.5, 0.90), hold(0.5, 0.80), hold(0.5, 0.70),
                     hold(0.5, 0.60), hold(0.5, 0.30)]
        let shrunk = holds.map {
            CGRect(x: $0.minX * 0.5 + 0.25, y: $0.minY * 0.5 + 0.25,
                   width: $0.width * 0.5, height: $0.height * 0.5)
        }
        let a = LineEngine.read(holds: holds)
        let b = LineEngine.read(holds: shrunk)
        #expect(a?.moves.map(\.kind) == b?.moves.map(\.kind))
        #expect(abs((a?.longest?.reach ?? 0) - (b?.longest?.reach ?? 1)) < 0.001)
    }

    /// The caveat has to say the three things the photo cannot see.
    @Test func theCaveatNamesWhatItCannotSee() {
        let c = LineEngine.caveat.lowercased()
        #expect(c.contains("faces"))
        #expect(c.contains("steep"))
        #expect(c.contains("beta"))
    }
}

/// What to try after a fall. Body, never route.
@Suite("Fall advice")
struct FallAdviceTests {

    private func frame(t: Double, com: CGPoint, hands: Double, feet: Double,
                       elbow: Double = 180) -> PoseFrame {
        // A straight arm puts the wrist directly below the elbow below the
        // shoulder; bending it swings the wrist out sideways.
        let bendOut = (180 - elbow) / 180 * 0.12
        let joints: [JointID: Joint] = [
            .leftShoulder: Fixture.joint(com.x - 0.04, com.y - 0.10),
            .rightShoulder: Fixture.joint(com.x + 0.04, com.y - 0.10),
            .leftElbow: Fixture.joint(com.x - 0.04 - bendOut, com.y - 0.16),
            .rightElbow: Fixture.joint(com.x + 0.04 + bendOut, com.y - 0.16),
            .leftWrist: Fixture.joint(hands - 0.06, com.y - 0.22),
            .rightWrist: Fixture.joint(hands + 0.06, com.y - 0.22),
            .leftHip: Fixture.joint(com.x - 0.03, com.y + 0.10),
            .rightHip: Fixture.joint(com.x + 0.03, com.y + 0.10),
            .leftAnkle: Fixture.joint(feet - 0.03, com.y + 0.28),
            .rightAnkle: Fixture.joint(feet + 0.03, com.y + 0.28)
        ]
        return PoseFrame(time: t, joints: joints, com: com, meanConfidence: 0.9)
    }

    @Test func swingingLeftSuggestsTheSecondForce() {
        // Contacts all to the right, body out to the left.
        let frames = (0..<60).map { i in
            frame(t: Double(i) / 30, com: CGPoint(x: 0.25, y: 0.5),
                  hands: 0.70, feet: 0.68)
        }
        let advice = FallAdvice.suggestions(frames: frames, fellAt: 2.0)
        #expect(advice.first?.move.contains("Flag") == true)
        // Swung out to the left, so the counterweight goes right.
        #expect(advice.first?.move.contains("right") == true)
        #expect(advice.first?.because.contains("left") == true)
    }

    @Test func aBodyInsideItsContactsGetsNoSwingAdvice() {
        let frames = (0..<60).map { i in
            frame(t: Double(i) / 30, com: CGPoint(x: 0.5, y: 0.5),
                  hands: 0.5, feet: 0.5)
        }
        let advice = FallAdvice.suggestions(frames: frames, fellAt: 2.0)
        #expect(!advice.contains { $0.move.contains("Flag") })
    }

    @Test func bentArmsAreCalledOut() {
        let frames = (0..<60).map { i in
            frame(t: Double(i) / 30, com: CGPoint(x: 0.5, y: 0.5),
                  hands: 0.5, feet: 0.5, elbow: 95)
        }
        let advice = FallAdvice.suggestions(frames: frames, fellAt: 2.0)
        #expect(advice.contains { $0.move.contains("Straighten") })
    }

    @Test func nothingToSayIsNothingSaid() {
        #expect(FallAdvice.suggestions(frames: [], fellAt: 3).isEmpty)
    }

    /// The caveat is the load-bearing sentence on this whole feature.
    @Test func theCaveatRefusesToNameAHold() {
        let c = FallAdvice.caveat.lowercased()
        #expect(c.contains("never seen the wall"))
        #expect(c.contains("which hold"))
    }

    /// Every suggestion has to quote the number it came from.
    @Test func everySuggestionShowsItsWorking() {
        let frames = (0..<60).map { i in
            frame(t: Double(i) / 30, com: CGPoint(x: 0.22, y: 0.5),
                  hands: 0.72, feet: 0.70, elbow: 100)
        }
        let advice = FallAdvice.suggestions(frames: frames, fellAt: 2.0)
        #expect(advice.count >= 2)
        #expect(advice.allSatisfy { $0.because.contains(where: \.isNumber) })
    }
}

/// The line read as a sequence.
@Suite("The line as a sequence")
struct LineSequenceTests {
    private func rect(_ x: Double, _ y: Double) -> CGRect {
        CGRect(x: x, y: y, width: 0.04, height: 0.04)
    }

    /// One line per move, numbered from the bottom, and the swing cue given
    /// once rather than on every sideways move.
    @Test("A traverse gets one cue, not one per move")
    func oneCuePerKind() throws {
        // Five holds walking across the wall with a little rise each time.
        let holds = [rect(0.10, 0.80), rect(0.30, 0.76), rect(0.50, 0.72),
                     rect(0.70, 0.68), rect(0.90, 0.64)]
        let line = try #require(LineEngine.read(holds: holds))
        let steps = LineEngine.sequence(line)
        #expect(steps.count == line.moves.count)
        #expect(steps.first?.hasPrefix("1 to 2:") == true)
        let cues = steps.filter { $0.contains("Flag the trailing foot") }.count
        #expect(cues <= 1, "the swing cue was repeated \(cues) times")
        #expect(steps.allSatisfy { $0.contains("right") }, "\(steps)")
    }
}

/// A thumb on a finding stays with the climb.
@Suite("Helpful or not", .serialized) @MainActor
struct FindingRatingTests {
    @Test("A thumb is saved, and tapping it again withdraws it")
    func thumbsPersist() async throws {
        let store = Store.shared
        try? await store.deleteAccount()
        store.continueLocally(name: "Katie")
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.findings = [Finding(kind: .bentArms, severity: .moderate, start: 1, end: 2, message: "m")]
        store.save(climb)
        let finding = climb.findings[0]

        store.rate(finding, in: climb, helpful: false)
        #expect(store.climbs.first { $0.id == climb.id }?.findings[0].helpful == false)
        store.rate(finding, in: climb, helpful: true)
        #expect(store.climbs.first { $0.id == climb.id }?.findings[0].helpful == true)
        store.rate(finding, in: climb, helpful: true)
        #expect(store.climbs.first { $0.id == climb.id }?.findings[0].helpful == nil)
    }
}
