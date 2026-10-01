import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// The sequence the planner chooses.
@Suite("Planning the sequence")
struct PlanTests {
    private func hold(_ x: Double, _ y: Double, _ s: Double = 0.05) -> CGRect {
        CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
    }

    /// A ladder of holds, left and right by turns: the hands alternate up
    /// it and every hold is used in order.
    @Test func aLadderIsClimbedHandOverHand() throws {
        var holds: [CGRect] = []
        for i in 0..<8 { holds.append(hold(i % 2 == 0 ? 0.42 : 0.58, 0.85 - Double(i) * 0.09)) }
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1], finishes: [7]))
        let seq = try #require(BetaEngine.read(line: line, shape: .average))
        let plan = try #require(seq.plan)
        #expect(plan.steps.count >= 6, "\(plan.steps)")
        // Alternating: no hand moves twice in a row.
        for (a, b) in zip(plan.steps, plan.steps.dropFirst()) { #expect(a.hand != b.hand) }
        // Ends with both hands on the finish.
        let last = try #require(plan.states.last)
        #expect(last.left == line.hands.firstIndex(of: holds[7]) && last.right == line.hands.firstIndex(of: holds[7]))
    }

    /// A hand never goes down, and never to a foot hold.
    @Test func handsGoUpAndNeverToAFootHold() throws {
        var holds: [CGRect] = []
        for i in 0..<6 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.8 - Double(i) * 0.1)) }
        holds.append(hold(0.5, 0.95, 0.015))   // a chip below the start
        holds.append(hold(0.5, 0.5, 0.012))    // a chip in the middle
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let hands = line.hands.map { CGPoint(x: $0.midX, y: $0.midY) }
        for (a, b) in zip(plan.states, plan.states.dropFirst()) {
            #expect(hands[b.left].y <= hands[a.left].y + 0.01 && hands[b.right].y <= hands[a.right].y + 0.01)
        }
        #expect(line.feet.count == 2)
    }

    /// A hold off to the side that the line does not need is skipped: the
    /// plan goes straight up rather than touching everything.
    @Test func aPointlessHoldIsSkipped() throws {
        let holds = [hold(0.45, 0.85), hold(0.55, 0.85), hold(0.45, 0.72), hold(0.55, 0.6),
                     hold(0.15, 0.66), hold(0.45, 0.48), hold(0.5, 0.36)]
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1], finishes: [6]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let far = try #require(line.hands.firstIndex(of: holds[4]))
        #expect(!plan.order.contains(far), "\(plan.order)")
    }

    /// One start sticker: both hands on it first.
    @Test func oneStartIsMatched() throws {
        let holds = [hold(0.5, 0.85), hold(0.45, 0.7), hold(0.55, 0.58), hold(0.5, 0.45)]
        let line = try #require(LineEngine.read(holds: holds, starts: [0], finishes: [3]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        #expect(plan.states.first?.left == plan.states.first?.right)
        let words = BetaEngine.describe(plan, line: line)
        #expect(words.first == "Start with both hands on 1.")
        #expect(words.dropFirst().allSatisfy { $0.hasPrefix("Left hand") || $0.hasPrefix("Right hand") })
    }

    /// Without stickers the plan still runs, from the lowest holds to the top.
    @Test func noStickersStillPlans() throws {
        var holds: [CGRect] = []
        for i in 0..<6 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.85 - Double(i) * 0.1)) }
        let line = try #require(LineEngine.read(holds: holds))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let top = try #require(line.hands.firstIndex(of: holds[5]))
        #expect(plan.states.last?.left == top && plan.states.last?.right == top)
    }

    @Test func finishStickersNameTheirHolds() {
        let holds = [hold(0.5, 0.9), hold(0.5, 0.4), hold(0.6, 0.4)]
        let tags = [RouteScanner.Tag(kind: .finish, point: CGPoint(x: 0.5, y: 0.44)),
                    RouteScanner.Tag(kind: .finish, point: CGPoint(x: 0.6, y: 0.44))]
        #expect(CoverageEngine.finishHolds(holds: holds, tags: tags) == [1, 2])
    }
}
