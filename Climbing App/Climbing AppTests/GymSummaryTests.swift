import Testing
import Foundation
@testable import ClimbingApp

/// The line under a gym's name.
@Suite("Gym summary")
struct GymSummaryTests {

    private func climb(_ name: String, sent: Bool) -> LibraryEntry {
        var c = Fixture.climb(path: Fixture.straightPath(), entropy: 1, label: name)
        c.sent = sent
        return LibraryEntry(attempts: [c])
    }

    private func route(_ name: String, sent: Bool) -> Route {
        var r = Route(gymID: UUID(), name: name, grade: "V3",
                      colorHex: "#CC3333", photoFilename: "x.jpg", holds: [])
        r.sent = sent
        return r
    }

    /// The bug, as it appeared: three ticked climbs and nothing scanned, under
    /// a heading that said nought sent.
    @Test("Ticked climbs count as sent")
    func climbsCountAsSent() {
        let line = GymSummary.line(routes: [], climbed: [
            climb("Green V3", sent: false),
            climb("Green V0", sent: true),
            climb("Purple V4", sent: true),
            climb("Yellow V3", sent: true)
        ])
        #expect(line == "4 climbs · 3 sent")
    }

    /// Scanning is not mentioned at a gym where nothing has been scanned. A
    /// zero in a summary line is a fact nobody asked for.
    @Test("Nothing scanned is not mentioned")
    func scanningIsOnlyMentionedWhenItHappened() {
        let line = GymSummary.line(routes: [], climbed: [climb("Green V3", sent: false)])
        #expect(!line.contains("scanned"))
        #expect(line == "1 climb · 0 sent")
    }

    @Test("A route sent on the wall counts too")
    func scannedRoutesCountAsSent() {
        let line = GymSummary.line(routes: [route("Blue arete", sent: true),
                                            route("Red roof", sent: false)],
                                   climbed: [])
        #expect(line == "2 scanned · 1 sent")
    }

    /// The double count. Scan a problem, mark it sent on the wall, then film
    /// yourself on it and mark that sent: one route, one send.
    @Test("The same route sent twice is one send")
    func oneRouteIsOneSend() {
        let line = GymSummary.line(routes: [route("Blue arete", sent: true)],
                                   climbed: [climb("Blue arete", sent: true)])
        #expect(line == "1 climb · 1 scanned · 1 sent")
    }

    /// Names are how the library decides two clips are the same route, so the
    /// matching here has to be as forgiving as that is.
    @Test("Case does not make a second route")
    func caseDoesNotSplitARoute() {
        #expect(GymSummary.sent(routes: [route("BLUE ARETE", sent: true)],
                                climbed: [climb("Blue arete", sent: true)]) == 1)
    }

    @Test("A gym with nothing at it says so")
    func anEmptyGymSaysSo() {
        #expect(GymSummary.line(routes: [], climbed: []) == "Nothing here yet")
    }
}
