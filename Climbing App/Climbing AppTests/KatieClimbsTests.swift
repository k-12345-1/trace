import Testing
import Foundation
@testable import ClimbingApp

private final class KatieToken {}

/// What the app says about the app's own climber.
///
/// Five clips of her, filmed from the floor the way the app asks, tracked
/// on the Mac at ten frames a second and kept as fixtures. The findings
/// the app would give are printed, so a change to the engine can be read
/// against real climbing rather than against synthetic fixtures alone.
@Suite("Her own climbs", .serialized)
struct KatieClimbsTests {
    static let clips = ["katie0672", "katie0673", "katie0674", "katie0675", "katie0676"]

    static func frames(_ name: String) throws -> [PoseFrame] {
        let url = try #require(Bundle(for: KatieToken.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
    }

    /// A resting arm reads about a hundred and fifty in the picture. Two of
    /// her clean climbs used to be told their arms were bent at 149 and 153.
    @Test("A resting arm at a hundred and fifty is not a bent arm")
    func aRestingArmIsNotBent() throws {
        for name in ["katie0673", "katie0676"] {
            let all = try Self.frames(name)
            let m = MetricsEngine.compute(frames: all)
            #expect(m.staticElbowAngle >= 145, "\(name): \(m.staticElbowAngle)")
            let findings = FindingEngine.findings(from: m, frames: MetricsEngine.ascent(all))
            #expect(!findings.contains { $0.kind == .bentArms }, "\(name) was told its arms were bent")
        }
    }

    @Test func printWhatTheAppSays() throws {
        for name in Self.clips {
            let all = try Self.frames(name)
            let climbing = MetricsEngine.ascent(all)
            let m = MetricsEngine.compute(frames: all)
            let findings = FindingEngine.findings(from: m, frames: climbing)
            let t = TechniqueEngine.read(frames: climbing)
            print(String(format: "KATIE %@ frames %d ascent %d tracking %.2f staticElbow %.0f comOffset %.2f waste %@ pauses %.1f/%.1f swing %.1f footResets %d", name, all.count, climbing.count, m.trackingConfidence, m.staticElbowAngle, m.comOffsetFromFeet, m.moveWaste.map { String(format: "%.2f", $0) } ?? "nil", m.pauseTotal, m.duration, m.swingTotal, m.footAdjustments))
            print(String(format: "KATIE %@ reaches %d feetStayed %d square %d/%d hipsBehind %d/%d lockOff %@ flared %.1f highSteps %d/%d", name, t.upwardReaches.count, t.feetStayed.count, t.squareAndBent.count, t.hipJudged, t.hipsBehind.count, t.hipsJudgedForLead, t.longestLockOff.map { String(format: "%.1fs", $0.duration) } ?? "none", t.flaredSeconds, t.highSteps.count, t.steps.count))
            for f in findings { print("KATIE \(name)   \(f.severity.label) · \(f.kind.title) @\(FindingEngine.timecode(f.start)): \(f.message)") }
            if findings.isEmpty { print("KATIE \(name)   clean") }
        }
    }
}
