import Foundation

/// What went well, measured the same way as what did not.
///
/// Trace only ever told climbers what leaked. A page of eight things you did
/// badly is not a coach, it is an audit, and it is also a false picture: a
/// climb that raised three findings did forty other things competently and the
/// screen said nothing about any of them.
///
/// The rule here is the one that keeps it worth reading. A strength is a
/// measurement that is plainly good, judged against the same numbers that raise
/// a finding, with a gap between the two so nothing is ever both. Where the
/// measurement could not be taken, there is no strength: a climb with no
/// dynamic moves in it does not get praised for its deadpoint timing, and a
/// climb Trace could barely see gets nothing at all. Where nothing clears the
/// bar, it says nothing, because praise handed out for turning up is worth what
/// it costs.
enum StrengthEngine {

    enum Kind: String, Codable, CaseIterable {
        case straightArms, direct, movingWell, feetStayed, overTheFeet
        case insideContacts, timedWell, smoothForYou

        var title: String {
            switch self {
            case .straightArms:   return "Hanging off bone"
            case .direct:         return "Straight to the next hold"
            case .movingWell:     return "You kept moving"
            case .feetStayed:     return "Feet stayed where you put them"
            case .overTheFeet:    return "Weight over your feet"
            case .insideContacts: return "Always between your hands and feet"
            case .timedWell:      return "Caught at the top of the arc"
            case .smoothForYou:   return "Smoother than your usual"
            }
        }

        /// Why it is worth something, in one line. Same register as a finding's
        /// correction: what it bought you, not what it says about you.
        var why: String {
            switch self {
            case .straightArms:
                return "Your arms carried you on bone rather than muscle, so the clock your forearms run on barely started."
            case .direct:
                return "Almost everything you travelled took you toward the next hold."
            case .movingWell:
                return "You spent almost none of the climb hanging still, which is where grip goes without ground being gained."
            case .feetStayed:
                return "Every foot went down once and stayed. Your hands never took the weight back."
            case .overTheFeet:
                return "Your weight sat over your feet, so your fingers held you on rather than holding you up."
            case .insideContacts:
                return "Your weight stayed between your contacts, so nothing had to resist a swing."
            case .timedWell:
                return "Your hand arrived when your body was weightless, which is when a hold has least to hold."
            case .smoothForYou:
                return "The force on your holds stayed steadier than it usually does on your climbs."
            }
        }
    }

    struct Strength: Identifiable {
        var id: String { kind.rawValue }
        let kind: Kind
        /// How far past the bar it went, 0 to 1, for ordering.
        let margin: Double
        /// What the number actually was.
        let detail: String
    }

    // MARK: The bars
    //
    // Set clear of the thresholds that raise the matching finding, with room
    // between, so no climb is ever praised and corrected for the same thing.

    static let straightArmsFloor = 165.0       // finding fires below 155
    static let directCeiling = 0.10            // finding fires above 0.18
    static let stillShareCeiling = 0.08
    static let offsetCeiling = 0.20            // finding fires above 0.35
    static let bracketedFloor = 0.90
    static let deadpointCeiling = 70.0         // ms; finding fires above 120
    static let smootherBy = 0.4                // log jerk below their own median
    /// Long enough that placing your feet once is a result rather than an
    /// accident of a two move problem.
    static let footClimbSeconds = 8.0

    static let limit = 3

    static func strengths(from m: Metrics, priorJerk: [Double] = []) -> [Strength] {
        guard m.isTrustworthy else { return [] }
        var out: [Strength] = []

        if m.staticElbowAngle >= straightArmsFloor {
            out.append(Strength(
                kind: .straightArms,
                margin: scaled(m.staticElbowAngle - straightArmsFloor, over: 15),
                detail: "\(Int(m.staticElbowAngle.rounded()))° while still"))
        }

        // Nil means there were not enough moves to read, which is not the same
        // as a climb that went straight to every hold.
        if let waste = m.moveWaste, waste <= directCeiling {
            out.append(Strength(
                kind: .direct,
                margin: scaled(directCeiling - waste, over: directCeiling),
                detail: "\(Int(((1 - waste) * 100).rounded()))% of your travel was toward the next hold"))
        }

        if m.duration > 0 {
            let share = m.pauseTotal / m.duration
            if share <= stillShareCeiling {
                out.append(Strength(
                    kind: .movingWell,
                    margin: scaled(stillShareCeiling - share, over: stillShareCeiling),
                    detail: "\(Int((share * 100).rounded()))% of the climb not moving"))
            }
        }

        if m.footAdjustments == 0, m.duration >= footClimbSeconds {
            out.append(Strength(kind: .feetStayed, margin: 0.7,
                                detail: "No foot was placed twice"))
        }

        if m.comOffsetFromFeet > 0, m.comOffsetFromFeet <= offsetCeiling {
            out.append(Strength(
                kind: .overTheFeet,
                margin: scaled(offsetCeiling - m.comOffsetFromFeet, over: offsetCeiling),
                detail: "\(Int((m.comOffsetFromFeet * 100).rounded()))% of a torso length to the side"))
        }

        if m.bracketedFraction >= bracketedFloor {
            out.append(Strength(
                kind: .insideContacts,
                margin: scaled(m.bracketedFraction - bracketedFloor, over: 1 - bracketedFloor),
                detail: "\(Int((m.bracketedFraction * 100).rounded()))% of the climb between your contacts"))
        }

        if m.hasDynamicMoves, m.meanDeadpointError <= deadpointCeiling {
            out.append(Strength(
                kind: .timedWell,
                margin: scaled(deadpointCeiling - m.meanDeadpointError, over: deadpointCeiling),
                detail: "\(Int(m.meanDeadpointError.rounded())) ms off the apex"))
        }

        // Smoothness has no defensible absolute scale, so it is only ever a
        // strength against this climber's own earlier climbs, and only once
        // there are enough of them to have a usual.
        if priorJerk.count >= 3 {
            let sorted = priorJerk.sorted()
            let median = sorted[sorted.count / 2]
            if m.logJerk <= median - smootherBy {
                out.append(Strength(
                    kind: .smoothForYou,
                    margin: scaled(median - smootherBy - m.logJerk, over: 1),
                    detail: String(format: "%.1f against your usual %.1f", m.logJerk, median)))
            }
        }

        return Array(out.sorted { $0.margin > $1.margin }.prefix(limit))
    }

    private static func scaled(_ x: Double, over span: Double) -> Double {
        guard span > 0 else { return 0 }
        return min(1, max(0, x / span))
    }
}
