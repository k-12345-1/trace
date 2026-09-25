import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Reading movement across routes rather than on one of them.
@Suite("Movement patterns")
struct PatternTests {

    /// One climb on its own route, with the elbow angle and metrics named.
    private func climb(_ label: String, elbow: Double = 180, feet: Int = 0,
                       offset: Double = 0, ratio: Double = 1.2,
                       jerk: Double = 5, daysAgo: Double = 0,
                       confidence: Double = 0.9) -> Climb {
        Climb(recordedAt: Date().addingTimeInterval(-daysAgo * 86400),
              videoFilename: "x.mov", label: label,
              metrics: Fixture.metrics(elbow: elbow, jerk: jerk, ratio: ratio,
                                       feet: feet, offset: offset,
                                       confidence: confidence),
              findings: [], frames: [])
    }

    private func routes(_ n: Int, elbow: Double = 180, feet: Int = 0) -> [Climb] {
        (0..<n).map { climb("route \($0)", elbow: elbow, feet: feet) }
    }

    // MARK: How much it needs before it says anything

    @Test func threeRoutesIsNotAPattern() {
        #expect(PatternEngine.report(from: routes(3)) == nil)
    }

    @Test func fourRoutesIs() {
        #expect(PatternEngine.report(from: routes(4)) != nil)
    }

    /// Ten attempts at one problem describe the problem, not the climber.
    @Test func attemptsAtOneRouteAreNotRoutes() {
        let sieged = (0..<10).map { climb("the same boulder", daysAgo: Double($0)) }
        #expect(PatternEngine.distinctRoutes(sieged) == 1)
        #expect(PatternEngine.report(from: sieged) == nil)
    }

    @Test func untrackableClimbsDoNotCount() {
        let blurry = (0..<8).map { climb("route \($0)", confidence: 0.2) }
        #expect(PatternEngine.distinctRoutes(blurry) == 0)
        #expect(PatternEngine.report(from: blurry) == nil)
    }

    // MARK: Standing

    @Test func straightArmsReadAsStrong() {
        let report = PatternEngine.report(from: routes(5, elbow: 175))
        let arms = report?.readings.first { $0.kind == .bentArms }
        #expect(arms?.standing == .strong)
    }

    @Test func veryBentArmsReadAsTheWeakest() {
        let report = PatternEngine.report(from: routes(5, elbow: 118))
        let arms = report?.readings.first { $0.kind == .bentArms }
        #expect(arms?.standing == .weak)
        // Worst first, so it leads the list.
        #expect(report?.readings.first?.kind == .bentArms)
    }

    /// The flag line here is the flag line in FindingEngine: 155 degrees.
    @Test func theFlagLineMatchesASingleClimb() {
        let justUnder = PatternEngine.report(from: routes(5, elbow: 150))
        #expect(justUnder?.readings.first { $0.kind == .bentArms }?.standing == .working)
        let justOver = PatternEngine.report(from: routes(5, elbow: 160))
        #expect(justOver?.readings.first { $0.kind == .bentArms }?.standing == .solid)
    }

    @Test func strengthsAndWeaknessesSplitOnSolid() {
        let mixed = (0..<5).map { climb("route \($0)", elbow: 175, feet: 9) }
        guard let report = PatternEngine.report(from: mixed) else {
            Issue.record("expected a report"); return
        }
        #expect(report.strengths.contains { $0.kind == .bentArms })
        #expect(report.weaknesses.contains { $0.kind == .impreciseFeet })
        let weakKinds = Set(report.weaknesses.map(\.kind.rawValue))
        #expect(report.strengths.allSatisfy { !weakKinds.contains($0.kind.rawValue) })
    }

    // MARK: Best attempt per route

    @Test func theBestAttemptOnARouteIsTheOneCounted() {
        // One route, climbed badly then well. The good one is what counts, so a
        // dimension is read at what you can do rather than at your worst go.
        let attempts = [climb("crimp ladder", elbow: 100),
                        climb("crimp ladder", elbow: 176)]
        let d = PatternEngine.dimensions.first { $0.kind == .bentArms }!
        let best = PatternEngine.bestPerRoute(attempts, for: d)
        #expect(best.count == 1)
        #expect(best.first?.metrics.staticElbowAngle == 176)
    }

    // MARK: Metrics that mean nothing are left out, not counted as zero

    @Test func aTraverseContributesNoPathRatio() {
        // Zero path ratio is MetricsEngine declining to answer, not a perfectly
        // straight line. Counted as zero it would read as a strength.
        let d = PatternEngine.dimensions.first { $0.kind == .wandering }!
        let traverse = Fixture.metrics(ratio: 0)
        #expect(PatternEngine.usableValue(d, in: traverse) == nil)
    }

    @Test func aStaticClimbContributesNoDeadpointTiming() {
        let d = PatternEngine.dimensions.first { $0.kind == .mistimedDynamics }!
        let noDynamics = Fixture.metrics(deadpoints: [])
        #expect(noDynamics.hasDynamicMoves == false)
        #expect(PatternEngine.usableValue(d, in: noDynamics) == nil)
        let dynamic = Fixture.metrics(deadpoints: [0.2, -0.15])
        #expect(PatternEngine.usableValue(d, in: dynamic) != nil)
    }

    /// A dimension no route could be read on is absent, not zero.
    @Test func aDimensionWithNoDataIsAbsent() {
        let report = PatternEngine.report(from: routes(5))
        #expect(report?.readings.contains { $0.kind == .mistimedDynamics } == false)
    }

    // MARK: Direction

    @Test func sixRoutesGettingBetterReadsAsImproving() {
        // Older half bent, newer half straight. daysAgo runs backwards so the
        // straight ones are the recent ones.
        var climbs: [Climb] = []
        for i in 0..<4 { climbs.append(climb("old \(i)", elbow: 120, daysAgo: Double(20 - i))) }
        for i in 0..<4 { climbs.append(climb("new \(i)", elbow: 172, daysAgo: Double(4 - i))) }
        let d = PatternEngine.dimensions.first { $0.kind == .bentArms }!
        #expect(PatternEngine.direction(of: climbs, d: d) == .improving)
    }

    @Test func theSameNumberThroughoutIsFlatNotATrend() {
        let steady = (0..<8).map { climb("route \($0)", elbow: 150, daysAgo: Double(8 - $0)) }
        let d = PatternEngine.dimensions.first { $0.kind == .bentArms }!
        #expect(PatternEngine.direction(of: steady, d: d) == .flat)
    }

    @Test func fiveRoutesIsNotEnoughForADirection() {
        let few = (0..<5).map { climb("route \($0)", elbow: 150, daysAgo: Double(5 - $0)) }
        let d = PatternEngine.dimensions.first { $0.kind == .bentArms }!
        #expect(PatternEngine.direction(of: few, d: d) == nil)
    }

    /// Smoothness has a direction and deliberately no standing, because log
    /// dimensionless jerk has no absolute meaning.
    @Test func smoothnessIsATrendAndNeverAStanding() {
        #expect(PatternEngine.dimensions.contains { $0.kind == .lurchy } == false)
        var climbs: [Climb] = []
        for i in 0..<4 { climbs.append(climb("old \(i)", jerk: 12, daysAgo: Double(20 - i))) }
        for i in 0..<4 { climbs.append(climb("new \(i)", jerk: 6, daysAgo: Double(4 - i))) }
        #expect(PatternEngine.smoothnessDirection(climbs) == .improving)
    }

    @Test func medianIgnoresOneWildAttempt() {
        #expect(PatternEngine.median([1, 2, 3, 4, 900]) == 3)
        #expect(PatternEngine.median([2, 4]) == 3)
        #expect(PatternEngine.median([]) == 0)
    }
}

/// The way in while there is no authentication server.
@Suite("Demo account")
struct DemoAccountTests {

    @Test func theCredentialsAreTheOnesGivenOut() {
        #expect(DemoAccount.email == "trace@climb.co")
        #expect(DemoAccount.password == "ClimbOn!")
    }

    @Test func theAddressForgivesCaseAndWhitespace() {
        // iOS autocapitalizes the first letter of an email field, so a demo that
        // rejected "Trace@climb.co" would be unusable on the device it is for.
        #expect(DemoAccount.matches(email: "  Trace@Climb.co ", password: "ClimbOn!"))
    }

    @Test func thePasswordDoesNot() {
        #expect(!DemoAccount.matches(email: "trace@climb.co", password: "climbon!"))
        #expect(!DemoAccount.matches(email: "trace@climb.co", password: "ClimbOn"))
        #expect(!DemoAccount.matches(email: "trace@climb.co", password: " ClimbOn!"))
    }

    @Test func anotherAddressIsNotTheDemo() {
        #expect(!DemoAccount.matches(email: "demo@traceclimb.co", password: "ClimbOn!"))
    }
}
