import Foundation
import CoreGraphics

/// How much of the effort went into getting up the route.
///
/// ## What this is
///
/// Five steps, worst to best. It is a **composite of things Trace measures**,
/// weighted here, and not a measurement of its own: nobody is reading joules
/// off a climber. Every part of it is a number already on the climb, every
/// weight is written down below, and the grade always names the thing that cost
/// the most, so it can be argued with rather than just believed.
///
/// ## Why these five
///
/// Each one is energy spent that did not raise you up the wall, and each is
/// scale-free so it does not depend on how far away the phone was.
///
/// - **Round trips** are movement that ended where it began. The most direct
///   waste there is, so it carries the most weight.
/// - **Re-lifting** is height gained, lost and gained again. Lifting your own
///   mass is the one cost on a climb you cannot avoid, and paying it twice is
///   the one you can.
/// - **Between moves** is travel beyond the shortest path from each position to
///   the next one. Not beyond a straight line up the wall: a boulder does not
///   offer one, and a climber who followed a diagonal problem perfectly would
///   score badly against a vertical. Both ends of each of these lines are
///   places the climber actually was, so going further than one of them is a
///   detour they took rather than a shape the route forced on them.
/// - **Bent arms** while still is load held by muscle that a straight arm hands
///   to bone. It is not distance, it is the rate you burn while not moving.
/// - **Hanging about** is time under tension with nothing to show for it.
///
/// A component that cannot be read on this climb is dropped and the rest are
/// reweighted. A climb too short to have moves in it has nothing to say about
/// the travel between them, one with no still moments has no elbow angle worth
/// quoting, and averaging a zero in for either would read as a climber doing
/// well at something they never did.
enum EfficiencyEngine {

    enum Grade: Int, Comparable, CaseIterable {
        case veryInefficient = 1, inefficient, mixed, efficient, veryEfficient
        static func < (l: Grade, r: Grade) -> Bool { l.rawValue < r.rawValue }

        var label: String {
            switch self {
            case .veryEfficient:   return "Very efficient"
            case .efficient:       return "Efficient"
            case .mixed:           return "Mixed"
            case .inefficient:     return "Inefficient"
            case .veryInefficient: return "Very inefficient"
            }
        }
    }

    /// One thing that cost energy, and how much of the total it was.
    struct Component: Identifiable {
        let name: String
        /// 0 is free, 1 is as bad as this measure gets.
        let cost: Double
        let weight: Double
        /// What the number actually was, for showing.
        let detail: String

        var id: String { name }
        var contribution: Double { cost * weight }
    }

    struct Reading {
        let grade: Grade
        /// 0 is nothing wasted, 1 is everything.
        let cost: Double
        let components: [Component]

        /// The one that cost the most, which is what the grade is mostly about.
        var worst: Component? {
            components.max { $0.contribution < $1.contribution }
        }
    }

    // MARK: The rubric
    //
    // Each `ceiling` is the value at which that measure is counted as as bad as
    // it gets. They are judgements, set where a climber would call the thing
    // plainly bad, and they are here rather than buried so they can be moved.

    static let wasteCeiling   = 0.35     // share of travel that was a round trip
    static let liftCeiling    = 0.60     // extra height re-lifted, as a fraction
    static let wanderCeiling  = 0.45     // share of travel that was not toward the next position
    static let elbowFloor     = 170.0    // degrees; at or above this costs nothing
    static let elbowCeiling   = 115.0    // and at or below this costs everything
    static let pauseCeiling   = 0.50     // share of the climb spent not moving

    static let wasteWeight  = 0.28
    static let liftWeight   = 0.24
    static let wanderWeight = 0.18
    static let elbowWeight  = 0.18
    static let pauseWeight  = 0.12

    /// Cut points on the weighted cost. Below the first is the best grade.
    static let cuts: [Double] = [0.15, 0.30, 0.48, 0.68]

    // MARK: Reading one climb

    static func read(_ climb: Climb) -> Reading? {
        guard climb.metrics.isTrustworthy else { return nil }
        let m = climb.metrics
        let climbing = MetricsEngine.ascent(climb.frames)

        var parts: [Component] = []

        if let waste = WasteEngine.read(frames: climbing), waste.total > 0 {
            parts.append(Component(
                name: "Round trips",
                cost: clamp(waste.share / wasteCeiling),
                weight: wasteWeight,
                detail: "\(Int((waste.share * 100).rounded()))% of your travel ended where it began"))
        }

        if let lift = BodyScale.lift(path: m.comPath), lift.net > 0.0001 {
            parts.append(Component(
                name: "Re-lifting",
                cost: clamp((lift.ratio - 1) / liftCeiling),
                weight: liftWeight,
                detail: "\(Int(((lift.ratio - 1) * 100).rounded()))% of your height was gained twice"))
        }

        // Nil means there were not enough moves to read, not a perfect line.
        if let waste = m.moveWaste {
            parts.append(Component(
                name: "Between moves",
                cost: clamp(waste / wanderCeiling),
                weight: wanderWeight,
                detail: "\(Int((waste * 100).rounded()))% of your travel was not toward the next hold"))
        }

        if m.staticElbowAngle > 0 {
            parts.append(Component(
                name: "Bent arms",
                cost: clamp((elbowFloor - m.staticElbowAngle) / (elbowFloor - elbowCeiling)),
                weight: elbowWeight,
                detail: "\(Int(m.staticElbowAngle.rounded()))° while still"))
        }

        if m.duration > 0 {
            let share = m.pauseTotal / m.duration
            parts.append(Component(
                name: "Hanging about",
                cost: clamp(share / pauseCeiling),
                weight: pauseWeight,
                detail: "\(Int((share * 100).rounded()))% of the climb not moving"))
        }

        guard !parts.isEmpty else { return nil }

        // Reweight over what could actually be read.
        let total = parts.reduce(0) { $0 + $1.weight }
        let cost = parts.reduce(0) { $0 + $1.contribution } / total

        return Reading(grade: grade(for: cost), cost: cost,
                       components: parts.sorted { $0.contribution > $1.contribution })
    }

    static func grade(for cost: Double) -> Grade {
        for (i, cut) in cuts.enumerated() where cost < cut {
            return Grade(rawValue: 5 - i) ?? .mixed
        }
        return .veryInefficient
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// Said wherever the grade is, because a single letter grade invites more
    /// trust than a weighted average of five proxies has earned.
    static let caveat = "A weighted summary of five things Trace measures, not a measurement of energy. The largest part of it is named so you can judge it yourself."
}
