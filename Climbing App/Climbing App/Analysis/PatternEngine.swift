import Foundation

/// What your climbing looks like across routes, rather than on one of them.
///
/// A single climb says what happened on that boulder. This says what happens to
/// you: the dimensions where your movement is consistently good, the ones where
/// it consistently is not, and which way each is going.
///
/// Three rules keep it from claiming more than it has.
///
/// It reads across **distinct routes**, not attempts. Ten goes at one problem
/// describe that problem, and the thing they mostly measure is how tired you got
/// on it. One climb per route is taken, the best one, so a route you siege does
/// not outvote five you did once.
///
/// It compares you against **the same numbers that flag a single climb**, never
/// against other climbers. Trace has no population to compare you to, and
/// inventing one would be the most convincing possible way to be wrong.
///
/// And smoothness is **left out of the standings entirely**. Log dimensionless
/// jerk is dominated by the pose tracker's noise floor, so there is no absolute
/// value at which someone is smooth; it is only ever compared to your own
/// history, which makes it a trend and not a standing.
enum PatternEngine {

    /// Distinct routes before any of this is shown. Below four, a "pattern" is
    /// two climbs agreeing with each other.
    static let minimumRoutes = 4
    /// And before a direction is claimed, since a trend needs halves.
    static let minimumForTrend = 6

    // MARK: The dimensions

    /// One axis of movement, with the numbers that decide where you stand on it.
    ///
    /// `flag` and the severity cuts are the same values `FindingEngine` uses on
    /// a single climb, so a dimension you are "working on" here is one that gets
    /// flagged there. `strong` is the only number invented for this screen: it
    /// is where the dimension stops being merely unflagged and starts being a
    /// thing you are good at. Those are conventions, not measurements, and they
    /// are set roughly a third of the way past the flag line.
    struct Dimension {
        let kind: LeakKind
        /// True when a bigger number is better, which is only ever elbow angle.
        let higherIsBetter: Bool
        let strong: Double
        let flag: Double
        /// Past this you are not merely flagged, you are weak on it.
        let weak: Double
        let unit: (Double) -> String

        func isPast(_ value: Double, _ mark: Double) -> Bool {
            higherIsBetter ? value < mark : value > mark
        }
    }

    static let dimensions: [Dimension] = [
        Dimension(kind: .bentArms, higherIsBetter: true,
                  strong: 168, flag: 155, weak: 130,
                  unit: { "\(Int($0.rounded()))°" }),
        Dimension(kind: .weightOnArms, higherIsBetter: false,
                  strong: 0.22, flag: 0.35, weak: 0.70,
                  unit: { String(format: "%.2f torsos", $0) }),
        // A share of travel now, not a multiple of a straight line, so the
        // thresholds move with the measure rather than being read in the old
        // units and quietly meaning something else.
        Dimension(kind: .wandering, higherIsBetter: false,
                  strong: 0.12, flag: 0.18, weak: 0.32,
                  unit: { "\(Int(($0 * 100).rounded()))%" }),
        Dimension(kind: .impreciseFeet, higherIsBetter: false,
                  strong: 1, flag: 3, weak: 5,
                  unit: { String(format: "%.1f resets", $0) }),
        Dimension(kind: .hesitation, higherIsBetter: false,
                  strong: 0.12, flag: 0.35, weak: 0.60,
                  unit: { "\(Int(($0 * 100).rounded()))% stopped" }),
        Dimension(kind: .mistimedDynamics, higherIsBetter: false,
                  strong: 80, flag: 120, weak: 200,
                  unit: { "\(Int($0.rounded())) ms off" }),
        // Read as the share of the climb spent outside the contacts rather than
        // as seconds, because seconds reward a short climb for being short.
        Dimension(kind: .unopposed, higherIsBetter: false,
                  strong: 0.05, flag: 0.15, weak: 0.30,
                  unit: { "\(Int(($0 * 100).rounded()))% unopposed" }),
        // The coaches' list. Shares of moves, so a long climb is not faulted
        // for being long; a climb with too few moves to make a share is left
        // out of the reading rather than counted as clean.
        Dimension(kind: .overReaching, higherIsBetter: false,
                  strong: 0.2, flag: 0.5, weak: 0.75,
                  unit: { "\(Int(($0 * 100).rounded()))% feet still" }),
        Dimension(kind: .squareHips, higherIsBetter: false,
                  strong: 0.15, flag: 0.4, weak: 0.7,
                  unit: { "\(Int(($0 * 100).rounded()))% square" }),
        Dimension(kind: .lockOffHeld, higherIsBetter: false,
                  strong: 1.0, flag: 2.5, weak: 4.5,
                  unit: { String(format: "%.1f s held", $0) }),
        Dimension(kind: .elbowsFlared, higherIsBetter: false,
                  strong: 0.5, flag: 1.5, weak: 4.0,
                  unit: { String(format: "%.1f s flared", $0) }),
        Dimension(kind: .highStep, higherIsBetter: false,
                  strong: 0.1, flag: 0.3, weak: 0.55,
                  unit: { "\(Int(($0 * 100).rounded()))% high" })
    ]

    // MARK: A reading

    enum Standing: Int, Comparable {
        case weak = 0, working, solid, strong
        static func < (l: Standing, r: Standing) -> Bool { l.rawValue < r.rawValue }

        var label: String {
            switch self {
            case .strong:  return "Strong"
            case .solid:   return "Solid"
            case .working: return "Needs work"
            case .weak:    return "Weakest"
            }
        }
    }

    enum Direction { case improving, flat, slipping }

    struct Reading: Identifiable {
        let kind: LeakKind
        let standing: Standing
        /// Your median across the routes this could be read on.
        let median: Double
        let display: String
        /// How many routes carried a usable number for this dimension. Not every
        /// climb has one: a traverse has no path ratio, a static problem has no
        /// dynamic moves.
        let routes: Int
        let direction: Direction?

        var id: String { kind.rawValue }
    }

    struct Report {
        let readings: [Reading]
        /// Distinct routes behind the whole thing.
        let routes: Int
        /// Where smoothness is going, which is the one dimension with no standing.
        let smoothness: Direction?

        var strengths: [Reading] { readings.filter { $0.standing >= .solid } }
        var weaknesses: [Reading] { readings.filter { $0.standing <= .working } }
    }

    // MARK: Building it

    /// One climb per route: the best attempt, judged on the dimension being read.
    /// Grouped on the label, which is how attempts are grouped everywhere else.
    static func bestPerRoute(_ climbs: [Climb], for d: Dimension) -> [Climb] {
        let tracked = climbs.filter { $0.metrics.isTrustworthy }
        let byRoute = Dictionary(grouping: tracked) {
            $0.label.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return byRoute.values.compactMap { attempts in
            attempts.min { a, b in
                let x = FocusEngine.value(for: d.kind, in: a.metrics)
                let y = FocusEngine.value(for: d.kind, in: b.metrics)
                return d.higherIsBetter ? x > y : x < y
            }
        }
    }

    static func distinctRoutes(_ climbs: [Climb]) -> Int {
        Set(climbs.filter { $0.metrics.isTrustworthy }
            .map { $0.label.trimmingCharacters(in: .whitespaces).lowercased() }).count
    }

    static func report(from climbs: [Climb]) -> Report? {
        let routes = distinctRoutes(climbs)
        guard routes >= minimumRoutes else { return nil }

        var readings: [Reading] = []
        for d in dimensions {
            let best = bestPerRoute(climbs, for: d)
            let values = best.compactMap { usableValue(d, in: $0.metrics) }
            guard values.count >= minimumRoutes else { continue }

            let mid = median(values)
            let standing: Standing = d.isPast(mid, d.weak) ? .weak
                                   : d.isPast(mid, d.flag) ? .working
                                   : d.isPast(mid, d.strong) ? .solid : .strong

            readings.append(Reading(
                kind: d.kind,
                standing: standing,
                median: mid,
                display: d.unit(mid),
                routes: values.count,
                direction: direction(of: best, d: d)
            ))
        }
        guard !readings.isEmpty else { return nil }

        // Worst first. That is the order the screen wants and the order the
        // person needs; a list of strengths at the top would bury the answer.
        readings.sort { $0.standing < $1.standing }

        return Report(readings: readings, routes: routes,
                      smoothness: smoothnessDirection(climbs))
    }

    /// A metric that means nothing on this climb is left out rather than counted
    /// as a zero. A zero path ratio is MetricsEngine declining to answer, and a
    /// zero deadpoint error is a climb with no dynamic moves in it, which is not
    /// perfect timing.
    static func usableValue(_ d: Dimension, in m: Metrics) -> Double? {
        let v = FocusEngine.value(for: d.kind, in: m)
        switch d.kind {
        case .wandering:        return v > 0 ? v : nil
        case .mistimedDynamics: return m.hasDynamicMoves ? v : nil
        case .weightOnArms:     return v > 0 ? v : nil
        case .bentArms:         return v > 0 ? v : nil
        // A share that could not be made is not a zero.
        case .overReaching:     return m.feetStayedShare
        case .squareHips:       return m.squareReachShare
        case .highStep:         return m.highStepShare
        // Not FocusEngine's value, which is seconds. The share is what compares
        // across climbs of different lengths.
        case .unopposed:        return 1 - m.bracketedFraction
        default:                return v
        }
    }

    /// Which way a dimension is going, from the older half of the routes to the
    /// newer. A margin keeps noise from being called a direction.
    static let trendMargin = 0.08

    static func direction(of climbs: [Climb], d: Dimension) -> Direction? {
        let ordered = climbs.sorted { $0.recordedAt < $1.recordedAt }
        let values = ordered.compactMap { usableValue(d, in: $0.metrics) }
        guard values.count >= minimumForTrend else { return nil }

        let half = values.count / 2
        let before = median(Array(values.prefix(half)))
        let after = median(Array(values.suffix(values.count - half)))
        guard before != 0 else { return nil }

        let change = (after - before) / abs(before)
        guard abs(change) > trendMargin else { return .flat }
        let better = d.higherIsBetter ? change > 0 : change < 0
        return better ? .improving : .slipping
    }

    /// Smoothness, which has no standing and only a direction.
    static func smoothnessDirection(_ climbs: [Climb]) -> Direction? {
        let d = Dimension(kind: .lurchy, higherIsBetter: false,
                          strong: 0, flag: 0, weak: 0, unit: { _ in "" })
        let tracked = climbs.filter { $0.metrics.isTrustworthy }
        return direction(of: tracked, d: d)
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
