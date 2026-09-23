import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

// MARK: - Grades

@Suite("Grades")
struct GradeTests {

    @Test("V scale parses and orders")
    func vScale() {
        let vb = Grade.parse("VB")!, v0 = Grade.parse("V0")!, v7 = Grade.parse("V7")!
        #expect(vb.scale == .vScale)
        #expect(vb.index < v0.index)
        #expect(v0.index < v7.index)
        #expect(Grade.parse("V10")!.index > v7.index)
    }

    @Test("A plus sits above the bare grade and below the next one")
    func plusMinus() {
        let v4 = Grade.parse("V4")!, v4plus = Grade.parse("V4+")!, v5 = Grade.parse("V5")!
        #expect(v4.index < v4plus.index)
        #expect(v4plus.index < v5.index)
        #expect(Grade.parse("V4-")!.index < v4.index)
    }

    @Test("Yosemite parses with its letter")
    func yds() {
        let a = Grade.parse("5.10a")!, d = Grade.parse("5.10d")!, eleven = Grade.parse("5.11a")!
        #expect(a.scale == .yds)
        #expect(a.index < d.index)
        #expect(d.index < eleven.index)
        #expect(Grade.parse("5.9")!.index < a.index)
    }

    @Test("French parses, and a plus lands between letters")
    func french() {
        let a = Grade.parse("6a")!, aplus = Grade.parse("6a+")!, b = Grade.parse("6b")!
        #expect(a.scale == .french)
        #expect(a.index < aplus.index)
        #expect(aplus.index < b.index)
        #expect(Grade.parse("7a")!.index > b.index)
    }

    @Test("Nonsense is refused rather than guessed at")
    func rejects() {
        #expect(Grade.parse("") == nil)
        #expect(Grade.parse("pink") == nil)
        #expect(Grade.parse("V") == nil)
        #expect(Grade.parse("V99") == nil)
        #expect(Grade.parse("6z") == nil)
    }

    @Test("Different scales are not compared")
    func noCrossScale() {
        let v4 = Grade.parse("V4")!, yds = Grade.parse("5.11a")!
        #expect(v4.steps(from: yds) == nil)
        #expect(v4.steps(from: Grade.parse("V2")!) != nil)
    }
}

// MARK: - Route shape

@Suite("Route shape")
struct RouteShapeTests {

    private func route(_ holds: [CGRect], grade: String = "", sent: Bool = false) -> Route {
        Route(gymID: UUID(), name: "R", grade: grade, colorHex: "#FF0000",
              photoFilename: "x.jpg", holds: holds, sent: sent)
    }

    /// A column of holds of a given size, evenly spaced.
    private func column(count: Int, size: Double, gap: Double,
                        x: Double = 0.5, lastGap: Double? = nil) -> [CGRect] {
        var out: [CGRect] = []
        var y = 0.9
        for i in 0..<count {
            out.append(CGRect(x: x - size/2, y: y - size/2, width: size, height: size))
            y -= (i == count - 2 ? (lastGap ?? gap) : gap)
        }
        return out
    }

    @Test("Too few holds to measure returns nothing")
    func needsHolds() {
        #expect(RouteShape.measure(route([])) == nil)
        #expect(RouteShape.measure(route([CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)])) == nil)
    }

    @Test("Small holds far apart are reachier than big holds close together")
    func reachiness() {
        let sparse = RouteShape.measure(route(column(count: 5, size: 0.02, gap: 0.18)))!
        let dense = RouteShape.measure(route(column(count: 5, size: 0.08, gap: 0.06)))!
        #expect(sparse.reachiness > dense.reachiness)
    }

    @Test("Reachiness does not change when the whole photo is scaled")
    func reachinessIsDimensionless() {
        // The same route photographed from twice as far away.
        let near = RouteShape.measure(route(column(count: 6, size: 0.06, gap: 0.14)))!
        let far = RouteShape.measure(route(column(count: 6, size: 0.03, gap: 0.07)))!
        #expect(abs(near.reachiness - far.reachiness) < 0.001)
    }

    @Test("A traverse spreads wider than a line")
    func spread() {
        var wide: [CGRect] = []
        for i in 0..<6 {
            wide.append(CGRect(x: 0.1 + Double(i)*0.13, y: 0.5 - Double(i)*0.01,
                               width: 0.04, height: 0.04))
        }
        let traverse = RouteShape.measure(route(wide))!
        let line = RouteShape.measure(route(column(count: 6, size: 0.04, gap: 0.13)))!
        #expect(traverse.spread > line.spread)
    }

    @Test("One long move shows up as a spike")
    func spike() {
        let even = RouteShape.measure(route(column(count: 6, size: 0.04, gap: 0.12)))!
        let jumpy = RouteShape.measure(
            route(column(count: 6, size: 0.04, gap: 0.08, lastGap: 0.42)))!
        #expect(jumpy.spike > even.spike)
        #expect(even.spike < 1.2)
    }
}

// MARK: - Which route for which leak

@Suite("Recommendations")
struct RecommenderTests {

    private let gym = UUID()

    private func route(_ name: String, holds: [CGRect],
                       grade: String = "", sent: Bool = false) -> Route {
        Route(gymID: gym, name: name, grade: grade, colorHex: "#FF0000",
              photoFilename: "x.jpg", holds: holds, sent: sent)
    }

    private func column(count: Int, size: Double, gap: Double,
                        x: Double = 0.5, lastGap: Double? = nil) -> [CGRect] {
        var out: [CGRect] = []
        var y = 0.92
        for i in 0..<count {
            out.append(CGRect(x: x - size/2, y: y - size/2, width: size, height: size))
            y -= (i == count - 2 ? (lastGap ?? gap) : gap)
        }
        return out
    }

    private func row(count: Int, size: Double, gap: Double) -> [CGRect] {
        (0..<count).map { i in
            CGRect(x: 0.08 + Double(i)*gap, y: 0.5 - Double(i)*0.012,
                   width: size, height: size)
        }
    }

    /// Four routes of clearly different character.
    private var wall: [Route] {
        [
            route("Juggy ladder", holds: column(count: 9, size: 0.09, gap: 0.07)),
            route("Crimp line", holds: column(count: 7, size: 0.018, gap: 0.12)),
            route("The traverse", holds: row(count: 7, size: 0.05, gap: 0.12)),
            route("Big throw", holds: column(count: 5, size: 0.05, gap: 0.07, lastGap: 0.5))
        ]
    }

    private func focus(_ kind: LeakKind) -> Focus {
        Focus(kind: kind, startedAt: Date(), baseline: 110, latest: 112)
    }

    private func topPick(_ kind: LeakKind) -> String {
        RouteRecommender.suggest(routes: wall, focus: focus(kind))
            .first?.route.name ?? "none"
    }

    @Test("Bent arms sends you to the big holds close together")
    func bentArms() {
        #expect(topPick(.bentArms) == "Juggy ladder")
    }

    @Test("Imprecise feet sends you to the small holds far apart")
    func feet() {
        #expect(topPick(.impreciseFeet) == "Crimp line")
    }

    @Test("Weight on arms sends you sideways")
    func hips() {
        #expect(topPick(.weightOnArms) == "The traverse")
    }

    @Test("Wandering sends you to the narrowest line, not the traverse")
    func wandering() {
        #expect(topPick(.wandering) != "The traverse")
    }

    @Test("Mistimed dynamics sends you to the one long move")
    func dynamics() {
        #expect(topPick(.mistimedDynamics) == "Big throw")
    }

    @Test("Hesitation sends you to the route with fewest holds")
    func hesitation() {
        #expect(topPick(.hesitation) == "Big throw")
    }

    @Test("Nothing is recommended without a focus")
    func needsFocus() {
        #expect(RouteRecommender.suggest(routes: wall, focus: nil).isEmpty)
    }

    @Test("A resolved focus stops recommending")
    func resolvedFocus() {
        var f = focus(.bentArms)
        f.resolvedAt = Date()
        #expect(RouteRecommender.suggest(routes: wall, focus: f).isEmpty)
    }

    @Test("One route is not a choice, so nothing is offered")
    func needsAPool() {
        #expect(RouteRecommender.suggest(routes: [wall[0]], focus: focus(.bentArms)).isEmpty)
    }

    @Test("Unmeasurable routes are skipped, not ranked")
    func skipsUnmeasurable() {
        let junk = route("No holds", holds: [])
        let picks = RouteRecommender.suggest(routes: wall + [junk], focus: focus(.bentArms))
        #expect(!picks.contains { $0.route.name == "No holds" })
    }

    @Test("The ceiling is the hardest send on the scale most used")
    func ceiling() {
        let routes = [
            route("a", holds: column(count: 4, size: 0.05, gap: 0.1), grade: "V2", sent: true),
            route("b", holds: column(count: 4, size: 0.05, gap: 0.1), grade: "V5", sent: true),
            route("c", holds: column(count: 4, size: 0.05, gap: 0.1), grade: "V8", sent: false)
        ]
        #expect(RouteRecommender.ceiling(in: routes) == Grade.parse("V5"))
    }

    @Test("Nothing sent means no ceiling, and grade stops mattering")
    func noCeiling() {
        let routes = wall.map {
            Route(gymID: gym, name: $0.name, grade: "V4", colorHex: "#FF0000",
                  photoFilename: "x.jpg", holds: $0.holds, sent: false)
        }
        #expect(RouteRecommender.ceiling(in: routes) == nil)
        #expect(RouteRecommender.suggest(routes: routes, focus: focus(.bentArms))
            .allSatisfy { $0.gradeNote == nil })
    }

    @Test("A drill prefers something below your limit over something above it")
    func prefersEasier() {
        // Two routes of identical shape, differing only in grade.
        let holds = column(count: 8, size: 0.09, gap: 0.07)
        let routes = [
            route("Hard", holds: holds, grade: "V7"),
            route("Easy", holds: holds, grade: "V2"),
            route("Sent it", holds: column(count: 4, size: 0.02, gap: 0.2),
                  grade: "V4", sent: true)
        ]
        let picks = RouteRecommender.suggest(routes: routes, focus: focus(.bentArms))
        #expect(picks.first?.route.name == "Easy")
    }

    @Test("At most the asked-for number come back, best first")
    func limitAndOrder() {
        let picks = RouteRecommender.suggest(routes: wall, focus: focus(.bentArms), limit: 2)
        #expect(picks.count == 2)
        #expect(picks[0].score >= picks[1].score)
    }
}
