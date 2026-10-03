import Testing
import Foundation
@testable import ClimbingApp

/// What went well.
///
/// The rule that makes this worth reading is that nothing is ever both praised
/// and corrected, and that silence is allowed. Most of these tests are about
/// those two things rather than about any single strength.
@Suite("What went well")
struct StrengthTests {

    private func metrics(elbow: Double = 150, waste: Double? = 0.30,
                         pauseTotal: Double = 4, duration: Double = 20,
                         feet: Int = 4, offset: Double = 0.50,
                         bracketed: Double = 0.5, jerk: Double = 20,
                         deadpoints: [Double] = []) -> Metrics {
        Metrics(entropy: 1, logJerk: jerk, pathRatio: 1.4, staticElbowAngle: elbow,
                pauseCount: 3, pauseTotal: pauseTotal, footAdjustments: feet,
                comOffsetFromFeet: offset, deadpointOffsets: deadpoints,
                comPath: Fixture.straightPath(), duration: duration,
                trackingConfidence: 0.9, bracketedFraction: bracketed,
                moveWaste: waste, movingJerk: jerk)
    }

    private func kinds(_ s: [StrengthEngine.Strength]) -> [StrengthEngine.Kind] {
        s.map(\.kind)
    }

    // MARK: Silence

    /// A climb that did nothing well gets told nothing, rather than being
    /// congratulated on showing up.
    @Test("A poor climb is praised for nothing")
    func aPoorClimbGetsNothing() {
        #expect(StrengthEngine.strengths(from: metrics()).isEmpty)
    }

    /// And a clip Trace could not see is not praised either, for the same
    /// reason it is not corrected.
    @Test("An untracked climb says nothing")
    func anUntrackedClimbSaysNothing() {
        var m = metrics(elbow: 175, waste: 0.02)
        m.trackingConfidence = 0.2
        #expect(StrengthEngine.strengths(from: m).isEmpty)
    }

    // MARK: Never both

    /// The one that matters. Every bar here has to sit clear of the threshold
    /// that raises the matching finding, so no climb is ever told it did the
    /// same thing well and badly.
    @Test("Nothing is praised and corrected at once")
    func nothingIsBothWaysAtOnce() {
        let samples: [Metrics] = [
            metrics(elbow: 175, waste: 0.03, pauseTotal: 0.5, duration: 20,
                    feet: 0, offset: 0.10, bracketed: 0.97, jerk: 16,
                    deadpoints: [0.03, -0.02]),
            metrics(elbow: 166, waste: 0.10, pauseTotal: 1.5, duration: 20,
                    feet: 0, offset: 0.20, bracketed: 0.90, jerk: 18,
                    deadpoints: [0.06]),
            metrics(elbow: 150, waste: 0.30, pauseTotal: 6, duration: 20,
                    feet: 5, offset: 0.60, bracketed: 0.3, jerk: 22),
        ]
        for m in samples {
            let praised = Set(kinds(StrengthEngine.strengths(from: m)).map(\.rawValue))
            let corrected = Set(FindingEngine.findings(from: m, frames: [])
                                    .map(\.kind)
                                    .map(pairing))
            #expect(praised.intersection(corrected).isEmpty,
                    "both praised and corrected: \(praised.intersection(corrected))")
        }
    }

    /// Which finding contradicts which strength.
    private func pairing(_ kind: LeakKind) -> String {
        switch kind {
        case .bentArms:      return StrengthEngine.Kind.straightArms.rawValue
        case .wandering:     return StrengthEngine.Kind.direct.rawValue
        case .hesitation:    return StrengthEngine.Kind.movingWell.rawValue
        case .impreciseFeet: return StrengthEngine.Kind.feetStayed.rawValue
        case .weightOnArms:  return StrengthEngine.Kind.overTheFeet.rawValue
        case .unopposed:     return StrengthEngine.Kind.insideContacts.rawValue
        case .mistimedDynamics: return StrengthEngine.Kind.timedWell.rawValue
        case .lurchy:        return StrengthEngine.Kind.smoothForYou.rawValue
        // The coaches' list has no strength to contradict yet: nothing praises
        // feet-first reaching or tucked elbows, so nothing can clash with it.
        case .overReaching, .squareHips, .lockOffHeld, .elbowsFlared, .highStep, .hipsBehind:
            return "no strength for \(kind.rawValue)"
        }
    }

    // MARK: Only what was measured

    /// A climb with no dynamic moves in it is not congratulated on its
    /// deadpoint timing. There was no deadpoint.
    @Test("No dynamic moves means no praise for timing them")
    func noDynamicsNoTiming() {
        let m = metrics(elbow: 175, deadpoints: [])
        #expect(!kinds(StrengthEngine.strengths(from: m)).contains(.timedWell))
    }

    /// Nil move waste means too few moves to read, which is not the same as a
    /// climb that went straight to every hold.
    @Test("An unreadable line is not a direct one")
    func unreadableIsNotDirect() {
        let m = metrics(elbow: 175, waste: nil)
        #expect(!kinds(StrengthEngine.strengths(from: m)).contains(.direct))
    }

    /// Placing your feet once on a four second problem is not a result.
    @Test("Tidy feet on a very short climb do not count")
    func shortClimbsDoNotCountFeet() {
        let m = metrics(duration: 4, feet: 0)
        #expect(!kinds(StrengthEngine.strengths(from: m)).contains(.feetStayed))
    }

    /// Smoothness has no absolute scale, so it is a strength only against this
    /// climber's own history, and only once there is a history.
    @Test("Smoothness needs a history to be smooth against")
    func smoothnessNeedsAHistory() {
        let m = metrics(jerk: 15)
        #expect(!kinds(StrengthEngine.strengths(from: m)).contains(.smoothForYou))
        #expect(!kinds(StrengthEngine.strengths(from: m, priorJerk: [20, 21]))
                    .contains(.smoothForYou))
        #expect(kinds(StrengthEngine.strengths(from: m, priorJerk: [20, 21, 19, 20]))
                    .contains(.smoothForYou))
    }

    // MARK: How many

    /// Three at most, best first. A list of eight things you did well is a
    /// participation certificate.
    @Test("At most three, best first")
    func threeAtMost() {
        let m = metrics(elbow: 180, waste: 0.0, pauseTotal: 0, duration: 30,
                        feet: 0, offset: 0.02, bracketed: 1.0, jerk: 10,
                        deadpoints: [0.01])
        let out = StrengthEngine.strengths(from: m, priorJerk: [20, 20, 20, 20])
        #expect(out.count == StrengthEngine.limit)
        #expect(out.map(\.margin) == out.map(\.margin).sorted(by: >))
    }

    @Test("Every strength says what the number was")
    func everyStrengthCarriesItsNumber() {
        let m = metrics(elbow: 178, waste: 0.02, pauseTotal: 0, duration: 25)
        for s in StrengthEngine.strengths(from: m) {
            #expect(!s.detail.isEmpty)
            #expect(!s.kind.why.isEmpty)
        }
    }
}
