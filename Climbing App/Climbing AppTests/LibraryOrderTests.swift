import Testing
import Foundation
@testable import ClimbingApp

/// Arranging the library.
///
/// The sort is a pure function of its inputs, including the efficiency reading,
/// which is handed in rather than computed. That is what lets these tests name
/// the cost of each route instead of building a climb that happens to produce
/// one, and it is why the screen can hand in a cached value instead of running
/// the analysis for every comparison.
@Suite("Library order")
struct LibraryOrderTests {

    private func route(_ name: String, daysAgo: Double, sent: Bool = false) -> LibraryEntry {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1,
                                  daysAgo: daysAgo, label: name)
        climb.sent = sent
        return LibraryEntry(attempts: [climb])
    }

    private func names(_ entries: [LibraryEntry]) -> [String] { entries.map(\.name) }

    /// Costs by route name, so a test says what it means.
    private func cost(_ table: [String: Double?]) -> (LibraryEntry) -> Double? {
        { entry in table[entry.name] ?? nil }
    }

    private let nothing: (LibraryEntry) -> Double? = { _ in nil }

    // MARK: Recent

    @Test func newestFirst() {
        let list = [route("old", daysAgo: 9), route("new", daysAgo: 1),
                    route("middle", daysAgo: 5)]
        let sorted = LibraryOrder.sort(list, by: .recent, reversed: false, cost: nothing)
        #expect(names(sorted) == ["new", "middle", "old"])
    }

    @Test func reversingRecentGivesOldestFirst() {
        let list = [route("old", daysAgo: 9), route("new", daysAgo: 1)]
        let sorted = LibraryOrder.sort(list, by: .recent, reversed: true, cost: nothing)
        #expect(names(sorted) == ["old", "new"])
    }

    // MARK: Efficiency

    @Test func bestClimbedFirst() {
        let list = [route("messy", daysAgo: 1), route("clean", daysAgo: 2),
                    route("middling", daysAgo: 3)]
        let sorted = LibraryOrder.sort(
            list, by: .efficiency, reversed: false,
            cost: cost(["messy": 0.8, "clean": 0.1, "middling": 0.4]))
        #expect(names(sorted) == ["clean", "middling", "messy"])
    }

    @Test func reversingEfficiencyGivesWhatToWorkOn() {
        let list = [route("messy", daysAgo: 1), route("clean", daysAgo: 2)]
        let sorted = LibraryOrder.sort(list, by: .efficiency, reversed: true,
                                       cost: cost(["messy": 0.8, "clean": 0.1]))
        #expect(names(sorted) == ["messy", "clean"])
    }

    /// The important one. A route Trace could not measure has no place in an
    /// order by how well it was climbed, and "we could not tell" is not the
    /// answer at either end of the question.
    @Test func unmeasuredRoutesSinkInBothDirections() {
        let list = [route("unknown", daysAgo: 1), route("messy", daysAgo: 2),
                    route("clean", daysAgo: 3)]
        let costs = cost(["messy": 0.8, "clean": 0.1])

        let best = LibraryOrder.sort(list, by: .efficiency, reversed: false, cost: costs)
        #expect(names(best) == ["clean", "messy", "unknown"])

        let worst = LibraryOrder.sort(list, by: .efficiency, reversed: true, cost: costs)
        #expect(names(worst) == ["messy", "clean", "unknown"])
    }

    @Test func nothingMeasuredIsNotAnError() {
        let list = [route("b", daysAgo: 1), route("a", daysAgo: 2)]
        let sorted = LibraryOrder.sort(list, by: .efficiency, reversed: false, cost: nothing)
        #expect(sorted.count == 2)
        #expect(names(sorted) == ["a", "b"])
    }

    // MARK: Sent

    @Test func sentFirst() {
        let list = [route("project", daysAgo: 1), route("done", daysAgo: 2, sent: true)]
        let sorted = LibraryOrder.sort(list, by: .sent, reversed: false, cost: nothing)
        #expect(names(sorted) == ["done", "project"])
    }

    @Test func reversingSentGivesTheProjects() {
        let list = [route("done", daysAgo: 2, sent: true), route("project", daysAgo: 1)]
        let sorted = LibraryOrder.sort(list, by: .sent, reversed: true, cost: nothing)
        #expect(names(sorted) == ["project", "done"])
    }

    @Test func withinAGroupTheNewestComesFirst() {
        let list = [route("old send", daysAgo: 9, sent: true),
                    route("new send", daysAgo: 1, sent: true),
                    route("project", daysAgo: 5)]
        let sorted = LibraryOrder.sort(list, by: .sent, reversed: false, cost: nothing)
        #expect(names(sorted) == ["new send", "old send", "project"])
    }

    // MARK: It has to hold still

    /// Two routes that tie on the key must always come out the same way round.
    /// Without a total order the grid reshuffles every time the view recomputes,
    /// which reads as the list glitching rather than as a sort.
    @Test func tiesAreBrokenTheSameWayEveryTime() {
        let same = Date()
        func tied(_ name: String) -> LibraryEntry {
            var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1, label: name)
            climb.recordedAt = same
            return LibraryEntry(attempts: [climb])
        }
        let list = [tied("b"), tied("a"), tied("c")]
        let once = LibraryOrder.sort(list, by: .recent, reversed: false, cost: nothing)
        let again = LibraryOrder.sort(list.reversed(), by: .recent, reversed: false, cost: nothing)
        #expect(names(once) == ["a", "b", "c"])
        #expect(names(once) == names(again))
    }

    // MARK: What it says it is doing

    @Test func everyOrderSaysWhichEndIsOnTop() {
        for order in LibraryOrder.allCases {
            #expect(order.heading(reversed: false) != order.heading(reversed: true),
                    "\(order.label) reads the same in both directions")
        }
    }
}
