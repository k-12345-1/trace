import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The kinds of route a climber falls off.
@Suite("Climbing styles")
struct StyleTests {

    private func climb(_ label: String, sent: Bool = false, dynamic: Double? = 0.1,
                       reach: Double? = 0.8, holds: Set<ClimbNotes.HoldType> = [],
                       angle: ClimbNotes.WallAngle? = nil,
                       faults: [LeakKind] = [], daysAgo: Double = 0) -> Climb {
        var notes = ClimbNotes()
        notes.holdTypes = holds; notes.angle = angle
        return Climb(recordedAt: Date().addingTimeInterval(-daysAgo * 86400),
                     videoFilename: "x.mov", label: label,
                     metrics: Fixture.metrics(dynamicShare: dynamic, reachTorsos: reach),
                     findings: faults.map { Finding(kind: $0, severity: .moderate, start: 0, end: 1, message: "") },
                     frames: [], sent: sent, notes: notes.isEmpty ? nil : notes)
    }

    @Test func threeRoutesIsNotAReport() {
        let climbs = (0..<3).map { climb("r\($0)") }
        #expect(StyleEngine.report(from: climbs) == nil)
    }

    /// The defect this exists to find: static routes go, dynamic ones do not.
    @Test func dynamicRoutesAreTheOnesNotSent() throws {
        var climbs = (0..<4).map { climb("s\($0)", sent: true, dynamic: 0.1) }
        climbs += (0..<3).map { climb("d\($0)", sent: false, dynamic: 0.6, faults: [.overReaching]) }
        let report = try #require(StyleEngine.report(from: climbs))
        let worst = try #require(report.buckets.first)
        #expect(worst.id == "dynamic")
        #expect(worst.sent == 0 && worst.routes == 3)
        #expect(worst.commonFault == .overReaching)
        let best = try #require(report.buckets.first { $0.id == "static" })
        #expect(best.sent == 4)
    }

    @Test func aBucketNeedsThreeRoutes() throws {
        var climbs = (0..<4).map { climb("s\($0)", dynamic: 0.1) }
        climbs += (0..<2).map { climb("d\($0)", dynamic: 0.9) }
        let report = try #require(StyleEngine.report(from: climbs))
        #expect(!report.buckets.contains { $0.id == "dynamic" })
    }

    @Test func tagsMakeHoldAndAngleBuckets() throws {
        var climbs = (0..<3).map { climb("c\($0)", holds: [.crimps], angle: .overhang) }
        climbs += (0..<3).map { climb("j\($0)", sent: true, holds: [.jugs, .slopers]) }
        let report = try #require(StyleEngine.report(from: climbs))
        #expect(report.buckets.contains { $0.id == "hold.crimps" && $0.sent == 0 })
        #expect(report.buckets.contains { $0.id == "hold.jugs" && $0.sent == 3 })
        #expect(report.buckets.contains { $0.id == "hold.slopers" })
        #expect(report.buckets.contains { $0.id == "angle.overhang" })
        #expect(!report.buckets.contains { $0.id == "hold.pinches" })
        #expect(report.untagged == 0)
    }

    /// Ten goes at one problem are one route, and a send on any of them is a send.
    @Test func attemptsFoldIntoOneRoute() throws {
        var climbs = (0..<5).map { climb("the proj", sent: $0 == 4, dynamic: 0.7, daysAgo: Double(5 - $0)) }
        climbs += (0..<3).map { climb("d\($0)", dynamic: 0.7) }
        let report = try #require(StyleEngine.report(from: climbs))
        let dynamic = try #require(report.buckets.first { $0.id == "dynamic" })
        #expect(dynamic.routes == 4)
        #expect(dynamic.sent == 1)
    }

    /// A tag put on one attempt belongs to the route.
    @Test func aTagOnAnyAttemptCountsForTheRoute() {
        let climbs = [climb("p", holds: [.slopers]), climb("p", daysAgo: 1)]
        let route = StyleEngine.routes(from: climbs).first
        #expect(route?.holdTypes == [.slopers])
    }

    @Test func aRouteWithNoStyleReadingStaysOutOfThoseBuckets() throws {
        var climbs = (0..<4).map { climb("s\($0)", dynamic: nil, reach: nil, holds: [.jugs]) }
        climbs += [climb("t", dynamic: 0.1)]
        let report = try #require(StyleEngine.report(from: climbs))
        #expect(!report.buckets.contains { $0.id == "static" })
        #expect(report.buckets.contains { $0.id == "hold.jugs" })
    }

    @Test func theCommonFaultBreaksTiesOnSeverity() {
        let f = [Finding(kind: .bentArms, severity: .minor, start: 0, end: 1, message: ""),
                 Finding(kind: .highStep, severity: .costly, start: 0, end: 1, message: "")]
        #expect(StyleEngine.commonFault(in: f) == .highStep)
    }

    /// Notes written before the tags existed still decode, and the tags round-trip.
    @Test func oldNotesDecodeAndTagsRoundTrip() throws {
        let old = #"{"effort":3,"holds":2,"note":"slick"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ClimbNotes.self, from: old)
        #expect(decoded.effort == 3 && decoded.holdTypes.isEmpty && decoded.angle == nil)

        var notes = ClimbNotes()
        notes.holdTypes = [.crimps, .pockets]; notes.angle = .roof
        let back = try JSONDecoder().decode(ClimbNotes.self, from: JSONEncoder().encode(notes))
        #expect(back == notes)
        #expect(!notes.isEmpty)
    }

    /// Off the real clip, the style reading exists and is in range.
    @Test func theRealClimbHasAStyle() throws {
        let bundle = Bundle(for: StyleToken.self)
        let url = try #require(bundle.url(forResource: "realclimb", withExtension: "json"))
        let clip = try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
        let m = MetricsEngine.compute(frames: clip)
        let share = try #require(m.dynamicShare)
        #expect(share >= 0 && share <= 1)
        let reach = try #require(m.reachTorsos)
        #expect(reach > 0.5 && reach < 4, "\(reach)")
    }
}

private final class StyleToken {}
