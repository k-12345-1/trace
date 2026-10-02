import Testing
import Foundation
import UIKit
@testable import ClimbingApp

private final class WallToken {}

/// What the route page says about a route agrees with what it draws, on
/// every route the scanner finds on the real walls.
@Suite("Route descriptions on real walls")
struct RouteDescriptionTests {
    private func routes() throws -> [(String, String, LineEngine.Line, BetaEngine.Sequence)] {
        var out: [(String, String, LineEngine.Line, BetaEngine.Sequence)] = []
        for name in ["gymwall", "wall2", "wall3", "wall4", "wall5"] {
            let url = try #require(Bundle(for: WallToken.self).url(forResource: name, withExtension: "jpg"))
            let image = try #require(UIImage(data: Data(contentsOf: url))?.upright.cgImage)
            for s in RouteScanner.palette(in: image) {
                guard let line = LineEngine.read(holds: s.holds.map(\.rect)),
                      let seq = BetaEngine.read(line: line, shape: .average) else { continue }
                out.append((name, s.hex, line, seq))
            }
        }
        return out
    }

    /// The summary counts the holds the drawing shows.
    @Test func theSummaryCountsWhatIsDrawn() throws {
        let all = try routes()
        #expect(all.count >= 16)
        for (name, hex, line, _) in all {
            let summary = try #require(LineEngine.summary(line), "\(name) \(hex)")
            #expect(summary.hasPrefix("\(line.holds.count) holds"), "\(name) \(hex): \(summary)")
            if !line.feet.isEmpty {
                #expect(summary.contains("\(line.hands.count) for the hands"), "\(name) \(hex): \(summary)")
            }
        }
    }

    /// The sentences number holds the way the picture numbers them: the
    /// start names the first stance, every number named is a number
    /// drawn, and a hand is sent only to a hand hold.
    @Test func theSentencesMatchThePicture() throws {
        for (name, hex, line, seq) in try routes() {
            let plan = try #require(seq.plan, "\(name) \(hex): \(line.holds.count) holds, \(line.hands.count) hands, \(line.feet.count) feet, start \(line.startCount)")
            let words = BetaEngine.describe(plan, line: line)
            #expect(words.count == plan.steps.count + 1, "\(name) \(hex)")
            func number(_ i: Int) -> Int { (plan.order.firstIndex(of: i) ?? i) + 1 }
            let first = try #require(plan.states.first)
            let start = try #require(words.first)
            #expect(start.hasPrefix("Start with"), "\(name) \(hex): \(start)")
            #expect(start.contains("\(number(first.leftHand))") && start.contains("\(number(first.rightHand))"),
                    "\(name) \(hex): \(start)")
            // Every number in the words is a number on the picture.
            let drawn = Set(1...max(plan.order.count, 1))
            for w in words {
                let numbers = w.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                for n in numbers { #expect(drawn.contains(n), "\(name) \(hex): \(w) names \(n) of \(plan.order.count)") }
            }
            // Hands on hand holds, feet on foot holds or smearing, never both on one.
            let hands = Set(line.hands.compactMap { line.holds.firstIndex(of: $0) })
            let feet = Set(line.feet.compactMap { line.holds.firstIndex(of: $0) })
            for p in plan.states {
                #expect(hands.contains(p.leftHand) && hands.contains(p.rightHand), "\(name) \(hex) hand on \(p)")
                for f in [p.leftFoot, p.rightFoot] where f >= 0 {
                    #expect(feet.contains(f) || hands.contains(f), "\(name) \(hex) foot on \(f)")
                    #expect(f != p.leftHand && f != p.rightHand, "\(name) \(hex) foot and hand on \(f)")
                }
            }
            // And a foot goes no higher than the planner's high step: a
            // twentieth of a span above the hips.
            let highest = BetaEngine.highestFoot * seq.span - 0.001
            for (i, pose) in seq.stances.enumerated() {
                #expect(pose.leftFoot.y >= pose.hips.y + highest && pose.rightFoot.y >= pose.hips.y + highest,
                        "\(name) \(hex) stance \(i) of \(seq.stances.count): hips \(pose.hips.y) L \(pose.leftFoot.y) \(pose.leftFootHold.map { "hold \($0)" } ?? "smear") R \(pose.rightFoot.y) \(pose.rightFootHold.map { "hold \($0)" } ?? "smear") span \(seq.span)")
            }
        }
    }
}
