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
        let handSteps = plan.steps.filter { $0.limb.isHand }
        #expect(handSteps.count >= 6, "\(plan.steps)")
        // Hand over hand: no hand goes three times running.
        for i in 2..<handSteps.count {
            #expect(!(handSteps[i].hand == handSteps[i - 1].hand && handSteps[i].hand == handSteps[i - 2].hand))
        }
        // Ends with both hands on the finish.
        let last = try #require(plan.states.last)
        let top = line.holds.firstIndex(of: holds[7])
        #expect(last.leftHand == top && last.rightHand == top)
    }

    /// A hand never goes down, and never to a foot hold.
    @Test func handsGoUpAndNeverToAFootHold() throws {
        var holds: [CGRect] = []
        for i in 0..<6 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.8 - Double(i) * 0.1)) }
        holds.append(hold(0.5, 0.95, 0.015))   // a chip below the start
        holds.append(hold(0.5, 0.5, 0.012))    // a chip in the middle
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        let handSet = Set(line.hands.compactMap { line.holds.firstIndex(of: $0) })
        for (a, b) in zip(plan.states, plan.states.dropFirst()) {
            #expect(all[b.leftHand].y <= all[a.leftHand].y + 0.01 && all[b.rightHand].y <= all[a.rightHand].y + 0.01)
            #expect(handSet.contains(b.leftHand) && handSet.contains(b.rightHand))
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
        let far = try #require(line.holds.firstIndex(of: holds[4]))
        #expect(!plan.handOrder.contains(far), "\(plan.handOrder)")
    }

    /// One start sticker: both hands on it first.
    @Test func oneStartIsMatched() throws {
        let holds = [hold(0.5, 0.85), hold(0.45, 0.7), hold(0.55, 0.58), hold(0.5, 0.45)]
        let line = try #require(LineEngine.read(holds: holds, starts: [0], finishes: [3]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        #expect(plan.states.first?.leftHand == plan.states.first?.rightHand)
        let words = BetaEngine.describe(plan, line: line)
        #expect(words.first?.hasPrefix("Start with both hands on 1") == true)
        let limbs = ["Left hand", "Right hand", "Left foot", "Right foot"]
        #expect(words.dropFirst().allSatisfy { w in limbs.contains { w.hasPrefix($0) } })
    }

    /// Without stickers the plan still runs, from the lowest holds to the top.
    @Test func noStickersStillPlans() throws {
        var holds: [CGRect] = []
        for i in 0..<6 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.85 - Double(i) * 0.1)) }
        let line = try #require(LineEngine.read(holds: holds))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let top = try #require(line.holds.firstIndex(of: holds[5]))
        #expect(plan.states.last?.leftHand == top && plan.states.last?.rightHand == top)
    }

    @Test func finishStickersNameTheirHolds() {
        let holds = [hold(0.5, 0.9), hold(0.5, 0.4), hold(0.6, 0.4)]
        let tags = [RouteScanner.Tag(kind: .finish, point: CGPoint(x: 0.5, y: 0.44)),
                    RouteScanner.Tag(kind: .finish, point: CGPoint(x: 0.6, y: 0.44))]
        #expect(CoverageEngine.finishHolds(holds: holds, tags: tags) == [1, 2])
    }

    /// The feet are moves too. With foot chips under a ladder, the plan
    /// moves a foot up before a hand it could not otherwise reach, every
    /// foot hold it uses is below the hips, and no two limbs share a hold.
    @Test func theFeetAreDeliberate() throws {
        var holds: [CGRect] = []
        for i in 0..<6 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.78 - Double(i) * 0.1)) }
        for i in 0..<5 { holds.append(hold(i % 2 == 0 ? 0.42 : 0.58, 0.92 - Double(i) * 0.1, 0.015)) }
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1], finishes: [5]))
        let seq = try #require(BetaEngine.read(line: line, shape: .average))
        let plan = try #require(seq.plan)
        let footSteps = plan.steps.filter { !$0.limb.isHand }
        #expect(footSteps.count >= 2, "\(plan.steps.map { "\($0.limb) \($0.to)" })")
        for p in plan.states {
            let limbs = [p.leftHand, p.rightHand, p.leftFoot, p.rightFoot].filter { $0 >= 0 }
            let feet = [p.leftFoot, p.rightFoot].filter { $0 >= 0 }
            #expect(Set(feet).isDisjoint(with: [p.leftHand, p.rightHand].filter { $0 != p.leftHand || p.leftHand == p.rightHand }) || feet.isEmpty)
            #expect(limbs.count == Set(limbs).count || p.leftHand == p.rightHand)
        }
        let step = BetaEngine.highestFoot * seq.span - 0.001
        for (i, pose) in seq.stances.enumerated() {
            #expect(pose.leftFoot.y >= pose.hips.y + step && pose.rightFoot.y >= pose.hips.y + step, "stance \(i)")
        }
        let words = BetaEngine.describe(plan, line: line)
        #expect(words.contains { $0.hasPrefix("Left foot") || $0.hasPrefix("Right foot") })
    }
}

/// Where an untagged route starts.
@Suite("Starting off the floor")
struct StartTests {
    private func hold(_ x: Double, _ y: Double, _ s: Double = 0.05) -> CGRect {
        CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
    }

    /// Without stickers the start is the lowest hand hold that has a foot
    /// hold below it, not the chip beside the mat.
    @Test func theStartHasSomethingToStandOn() throws {
        let holds = [hold(0.50, 0.95), hold(0.56, 0.93),            // two chips by the mat
                     hold(0.48, 0.78, 0.07), hold(0.56, 0.76, 0.06), // the start jugs
                     hold(0.50, 0.60), hold(0.52, 0.45), hold(0.50, 0.30)]
        let line = try #require(LineEngine.read(holds: holds))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let first = try #require(plan.states.first)
        let startY = min(line.holds[first.leftHand].midY, line.holds[first.rightHand].midY)
        #expect(startY <= 0.79, "started at \(line.holds[first.leftHand].midY)")
        #expect(line.holds[first.leftHand].midY < 0.9 && line.holds[first.rightHand].midY < 0.9)
    }
}

/// What the planner does when the finish cannot be reached, and when the
/// feet could stand.
@Suite("Planning at the edges")
struct PlanEdgeTests {
    private func hold(_ x: Double, _ y: Double, _ s: Double = 0.05) -> CGRect {
        CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
    }

    /// A top hold far out of reach of everything still leaves a plan, as
    /// high as the body can get. Before this the route page showed nothing.
    @Test func anUnreachableTopStillPlansAsHighAsItCan() throws {
        var holds: [CGRect] = []
        for i in 0..<5 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.85 - Double(i) * 0.09)) }
        holds.append(hold(0.95, 0.05))   // a speck of the colour on the ceiling
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let all = line.holds.map { CGPoint(x: $0.midX, y: $0.midY) }
        let last = try #require(plan.states.last)
        // Both hands finish on the finish, as a throw if nothing else.
        let top = line.holds.firstIndex(of: holds.min { $0.midY < $1.midY }!)
        #expect(last.leftHand == top && last.rightHand == top, "\(plan.states)")
        #expect(plan.steps.count >= 2)
    }

    /// Standing on one foot is not worse than smearing both: on a ladder
    /// with foot holds the plan stands.
    @Test func thePlanStandsWhenItCan() throws {
        var holds: [CGRect] = []
        for i in 0..<6 { holds.append(hold(i % 2 == 0 ? 0.45 : 0.55, 0.78 - Double(i) * 0.1)) }
        for i in 0..<5 { holds.append(hold(i % 2 == 0 ? 0.42 : 0.58, 0.92 - Double(i) * 0.1, 0.015)) }
        let line = try #require(LineEngine.read(holds: holds, starts: [0, 1], finishes: [5]))
        let plan = try #require(BetaEngine.read(line: line, shape: .average)?.plan)
        let planted = plan.states.filter { $0.leftFoot >= 0 || $0.rightFoot >= 0 }.count
        #expect(planted * 2 >= plan.states.count, "\(planted) of \(plan.states.count)")
    }
}

/// With a traced outline, the hand goes to the plastic.
@Suite("Hands on the outline")
struct ContactTests {
    @Test func aHandLandsOnTheTracedHold() throws {
        var holds: [CGRect] = []
        for i in 0..<5 { holds.append(CGRect(x: (i % 2 == 0 ? 0.40 : 0.56) - 0.03, y: 0.85 - Double(i) * 0.12 - 0.03, width: 0.06, height: 0.06)) }
        // Each hold's outline is a diamond inside its box.
        let outlines = holds.map { r in
            [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
        }
        let plain = try #require(LineEngine.read(holds: holds, starts: [0, 1]))
        let traced = try #require(LineEngine.read(holds: holds, starts: [0, 1], outlines: outlines))
        #expect(traced.outlines.allSatisfy { $0.count == 4 })
        let a = try #require(BetaEngine.read(line: plain, shape: .average)?.stances.first)
        let b = try #require(BetaEngine.read(line: traced, shape: .average)?.stances.first)
        // Plain: the hand is at the centre. Traced: on a point of the outline.
        #expect(holds.contains { abs($0.midX - a.leftHand.x) < 1e-6 && abs($0.midY - a.leftHand.y) < 1e-6 })
        #expect(outlines.flatMap { $0 }.contains { abs($0.x - b.leftHand.x) < 1e-6 && abs($0.y - b.leftHand.y) < 1e-6 })
    }
}
