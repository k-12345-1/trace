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

/// A figure through the line.
@Suite("A body on the line")
struct BetaTests {
    private func hold(_ x: Double, _ y: Double) -> CGRect {
        CGRect(x: x - 0.02, y: y - 0.02, width: 0.04, height: 0.04)
    }

    /// A ladder: hands alternate up the middle, feet find the holds below.
    private var ladder: [CGRect] {
        [hold(0.45, 0.90), hold(0.55, 0.80), hold(0.45, 0.70), hold(0.55, 0.60),
         hold(0.45, 0.50), hold(0.55, 0.40), hold(0.45, 0.30)]
    }

    @Test("One stance per pair of holds, hands on the holds")
    func handsAreOnTheHolds() throws {
        let line = try #require(LineEngine.read(holds: ladder))
        let seq = try #require(BetaEngine.read(line: line))
        #expect(seq.stances.count == line.holds.count - 1)
        for (i, s) in seq.stances.enumerated() {
            let a = line.holds[i], b = line.holds[i + 1]
            let hands = [s.leftHand, s.rightHand]
            #expect(hands.contains { abs($0.x - a.midX) < 1e-6 && abs($0.y - a.midY) < 1e-6 })
            #expect(hands.contains { abs($0.x - b.midX) < 1e-6 && abs($0.y - b.midY) < 1e-6 })
        }
    }

    @Test("The body hangs below the hands and the feet are below the hips")
    func theBodyHangs() throws {
        let line = try #require(LineEngine.read(holds: ladder))
        let seq = try #require(BetaEngine.read(line: line))
        for s in seq.stances {
            #expect(s.leftShoulder.y > min(s.leftHand.y, s.rightHand.y))
            #expect(s.hips.y > s.leftShoulder.y)
            #expect(s.leftFoot.y >= s.hips.y + BetaEngine.highestFoot * seq.span)
            #expect(s.rightFoot.y >= s.hips.y + BetaEngine.highestFoot * seq.span)
        }
    }

    /// Higher up the ladder there are holds below to stand on; at the start
    /// there are none, so the feet smear.
    @Test("Feet take holds when there are any, and smear when there are none")
    func feetFindHolds() throws {
        let line = try #require(LineEngine.read(holds: ladder))
        let seq = try #require(BetaEngine.read(line: line))
        let first = try #require(seq.stances.first)
        #expect(first.leftFootHold == nil && first.rightFootHold == nil)
        let later = seq.stances.dropFirst(3)
        #expect(later.contains { $0.leftFootHold != nil || $0.rightFootHold != nil },
                "no stance above the third found a foothold")
        // A foot is never on a hand's hold.
        for (i, s) in seq.stances.enumerated() {
            for f in [s.leftFootHold, s.rightFootHold].compactMap({ $0 }) {
                #expect(f != i && f != i + 1, "stance \(i) stood on a hand hold")
            }
        }
    }

    @Test("Scrubbing is continuous and ends on the last stance")
    func scrubbing() throws {
        let line = try #require(LineEngine.read(holds: ladder))
        let seq = try #require(BetaEngine.read(line: line))
        let a = try #require(seq.pose(at: 0)), z = try #require(seq.pose(at: 1))
        #expect(abs(a.hips.y - seq.stances.first!.hips.y) < 1e-9)
        #expect(abs(z.hips.y - seq.stances.last!.hips.y) < 1e-9)
        var last = a.hips.y
        for k in 1...50 {
            let p = try #require(seq.pose(at: Double(k) / 50))
            #expect(abs(p.hips.y - last) < 0.08, "jumped at \(k)")
            last = p.hips.y
        }
    }
}

extension BetaTests {
    /// Hands further apart than two arms used to produce NaN for every other
    /// joint, and a figure made of NaN is not drawn.
    @Test("A stance the body cannot make still has a body")
    func impossibleStanceStillDraws() throws {
        let holds = [hold(0.10, 0.90), hold(0.90, 0.88), hold(0.50, 0.60), hold(0.50, 0.30)]
        let line = try #require(LineEngine.read(holds: holds))
        let seq = try #require(BetaEngine.read(line: line))
        for s in seq.stances {
            for p in s.joints + [s.head] {
                #expect(p.x.isFinite && p.y.isFinite, "a joint went non-finite")
            }
            #expect(s.hips.y > min(s.leftHand.y, s.rightHand.y))
        }
    }
}

/// Hands and feet: the start holds first, and nothing a hand should not go to.
@Suite("Hands and feet on the line")
struct HandsAndFeetTests {
    private func hold(_ x: Double, _ y: Double, _ s: Double = 0.05) -> CGRect {
        CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
    }

    /// The defect: the sequence began on two foot chips low on the wall and
    /// the figure hung from them. With the start known, those are feet.
    @Test func theStartHoldsComeFirstAndBelowThemIsFeet() throws {
        let holds = [hold(0.45, 0.95, 0.02), hold(0.55, 0.93, 0.02), hold(0.5, 0.85, 0.02),
                     hold(0.4, 0.7), hold(0.6, 0.7), hold(0.5, 0.5), hold(0.5, 0.3)]
        let line = try #require(LineEngine.read(holds: holds, starts: [3, 4]))
        #expect(line.startCount == 2)
        #expect(line.hands.count == 4)
        #expect(line.hands[0] == holds[3] && line.hands[1] == holds[4])
        #expect(line.feet.count == 3)
        #expect(line.holds.count == 7)
    }

    @Test func aChipIsNeverAHandHold() throws {
        let holds = [hold(0.5, 0.9), hold(0.52, 0.8, 0.015), hold(0.5, 0.7), hold(0.5, 0.5), hold(0.5, 0.3)]
        let line = try #require(LineEngine.read(holds: holds))
        #expect(line.feet == [holds[1]])
        #expect(line.hands.count == 4)
    }

    /// With one start sticker the figure begins with both hands on it.
    @Test func oneStartMatchesBothHands() throws {
        let holds = [hold(0.5, 0.95, 0.02), hold(0.5, 0.8), hold(0.45, 0.6), hold(0.55, 0.4)]
        let line = try #require(LineEngine.read(holds: holds, starts: [1]))
        #expect(line.startCount == 1 && line.hands.first == holds[1])
        let seq = try #require(BetaEngine.read(line: line, shape: .average))
        let first = try #require(seq.stances.first)
        #expect(first.leftHand == first.rightHand)
        #expect(abs(first.leftHand.y - 0.8) < 0.001)
        // And no stance ever has a hand on the chip.
        for p in seq.stances { #expect(p.leftHand.y < 0.9 && p.rightHand.y < 0.9) }
    }

    @Test func theFigureStillStandsOnFootHolds() throws {
        // Start holds a hand's width apart, chips under them at shin height.
        let holds = [hold(0.45, 0.95, 0.02), hold(0.55, 0.93, 0.02), hold(0.45, 0.7), hold(0.55, 0.7), hold(0.5, 0.58)]
        let line = try #require(LineEngine.read(holds: holds, starts: [2, 3]))
        let seq = try #require(BetaEngine.read(line: line, shape: .average))
        let first = try #require(seq.stances.first)
        #expect(first.leftFootHold != nil || first.rightFootHold != nil)
    }

    @Test func startStickersNameTheirHolds() {
        let holds = [hold(0.5, 0.9, 0.02), hold(0.4, 0.7), hold(0.6, 0.7), hold(0.5, 0.4)]
        let tags = [RouteScanner.Tag(kind: .start, point: CGPoint(x: 0.4, y: 0.74)),
                    RouteScanner.Tag(kind: .start, point: CGPoint(x: 0.6, y: 0.74)),
                    RouteScanner.Tag(kind: .finish, point: CGPoint(x: 0.5, y: 0.44))]
        #expect(CoverageEngine.startHolds(holds: holds, tags: tags) == [1, 2])
    }
}
