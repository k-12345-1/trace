import Foundation
import CoreGraphics

/// What a scanned route is shaped like, and which routes suit the thing you are
/// working on.
///
/// The only thing Trace knows about a route is where its holds are in a photo,
/// so the only claims made here are about hold geometry. It cannot see the wall
/// angle, it does not know how the holds face, and it has no opinion about the
/// setter's intent.
///
/// Every feature below is deliberately dimensionless: a ratio of one measurement
/// in the photo to another. Absolute sizes are not comparable between routes,
/// because two photos of two walls were taken from two distances. Ratios inside
/// a single photo survive that.
struct RouteShape {
    let holdCount: Int
    /// Mean gap between consecutive holds up the wall, in units of hold size.
    /// High means small holds spread far apart; low means big holds close together.
    let reachiness: Double
    /// Width of the hold cloud over its height. High is a traverse, low is a line.
    let spread: Double
    /// The biggest gap over the average gap. High means one move stands out.
    let spike: Double

    static func measure(_ route: Route) -> RouteShape? {
        let holds = route.holds
        guard holds.count >= 3 else { return nil }

        // Hold size as a length, so it divides into a gap cleanly.
        let sizes = holds.map { ($0.width * $0.height).squareRoot() }
        let meanSize = sizes.reduce(0, +) / Double(sizes.count)
        guard meanSize > 0 else { return nil }

        // Gaps between holds in the order you would meet them going up.
        let up = holds.sorted { $0.midY > $1.midY }
        var gaps: [Double] = []
        for (a, b) in zip(up, up.dropFirst()) {
            let dx = b.midX - a.midX, dy = b.midY - a.midY
            gaps.append((dx * dx + dy * dy).squareRoot())
        }
        guard !gaps.isEmpty else { return nil }
        let meanGap = gaps.reduce(0, +) / Double(gaps.count)
        guard meanGap > 0 else { return nil }

        let xs = holds.map { $0.midX }, ys = holds.map { $0.midY }
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)

        return RouteShape(
            holdCount: holds.count,
            reachiness: meanGap / meanSize,
            spread: height > 0.001 ? width / height : 1,
            spike: (gaps.max() ?? meanGap) / meanGap
        )
    }
}

/// One route put forward, and why.
struct Recommendation: Identifiable {
    let route: Route
    let score: Double
    let reason: String
    /// How the grade sits against the hardest thing you have sent, when both are
    /// on the same scale and both are readable.
    let gradeNote: String?

    var id: UUID { route.id }
}

enum RouteRecommender {

    /// What each leak wants from a route, in one line for the climber.
    static func reason(for kind: LeakKind) -> String {
        switch kind {
        case .bentArms:
            return "Big holds, close together. You can stop on them and hang straight instead of fighting."
        case .weightOnArms:
            return "Spread wide across the wall, so reaching means turning a hip in rather than pulling straight."
        case .lurchy:
            return "Plenty of holds, evenly spaced. There is always somewhere to move to, so you can keep moving."
        case .impreciseFeet:
            return "Small holds a long way apart. A foot that lands twice will not stay on."
        case .hesitation:
            return "Few enough holds to read the whole thing from the ground before you leave it."
        case .wandering:
            return "Holds far enough apart that each move is its own commitment, so a reach that sets off and corrects shows."
        case .mistimedDynamics:
            return "One move much longer than the rest. It has to be thrown, so the timing is the move."
        case .unopposed:
            return "Holds spread wide on both sides of the line. Every reach then has somewhere on the far side to press against."
        }
    }

    /// How well a route suits a leak, 0 to 1, judged against the other routes it
    /// is competing with rather than against absolute numbers.
    static func fit(_ shape: RouteShape, for kind: LeakKind, among pool: [RouteShape]) -> Double {
        func rank(_ value: Double, _ all: [Double], ascending: Bool) -> Double {
            guard let lo = all.min(), let hi = all.max(), hi - lo > 1e-9 else { return 0.5 }
            let t = (value - lo) / (hi - lo)
            return ascending ? t : 1 - t
        }

        switch kind {
        case .bentArms:
            return rank(shape.reachiness, pool.map(\.reachiness), ascending: false)
        case .weightOnArms:
            return rank(shape.spread, pool.map(\.spread), ascending: true)
        case .lurchy:
            return 0.6 * rank(Double(shape.holdCount), pool.map { Double($0.holdCount) }, ascending: true)
                 + 0.4 * rank(shape.spike, pool.map(\.spike), ascending: false)
        case .impreciseFeet:
            return rank(shape.reachiness, pool.map(\.reachiness), ascending: true)
        case .hesitation:
            return rank(Double(shape.holdCount), pool.map { Double($0.holdCount) }, ascending: false)
        case .wandering:
            return rank(shape.spread, pool.map(\.spread), ascending: false)
        case .mistimedDynamics:
            return rank(shape.spike, pool.map(\.spike), ascending: true)
        case .unopposed:
            // Wide, like weight on your arms, because a route that only ever
            // goes straight up never offers the second contact to pull against.
            return rank(shape.spread, pool.map(\.spread), ascending: true)
        }
    }

    /// Most leaks are worked on below your limit, which is what every drill says.
    /// Mistimed dynamics is the exception: a throw you can already almost make is
    /// the only one worth timing.
    static func wantsEasier(_ kind: LeakKind) -> Bool {
        kind != .mistimedDynamics
    }

    /// The hardest grade among routes marked sent, per scale. Used as the level
    /// to aim below, and absent until something has been sent.
    static func ceiling(in routes: [Route]) -> Grade? {
        let sent = routes.filter(\.sent).compactMap { Grade.parse($0.grade) }
        guard !sent.isEmpty else { return nil }
        // The scale with the most sends is the one this climber actually uses.
        let byScale = Dictionary(grouping: sent, by: \.scale)
        guard let (_, grades) = byScale.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return grades.max { $0.index < $1.index }
    }

    /// Routes to try, best first.
    ///
    /// Returns nothing rather than something arbitrary when there is nothing to
    /// go on: no focus, or no scanned routes with enough holds to measure.
    static func suggest(routes: [Route], focus: Focus?, limit: Int = 3) -> [Recommendation] {
        guard let focus, !focus.isResolved else { return [] }
        let kind = focus.kind

        let measured = routes.compactMap { route -> (Route, RouteShape)? in
            RouteShape.measure(route).map { (route, $0) }
        }
        guard measured.count >= 2 else { return [] }

        let pool = measured.map(\.1)
        let top = ceiling(in: routes)

        let scored = measured.map { route, shape -> Recommendation in
            let shapeFit = fit(shape, for: kind, among: pool)
            let (gradeFit, note) = gradeScore(route: route, ceiling: top, kind: kind)
            return Recommendation(
                route: route,
                score: 0.75 * shapeFit + 0.25 * gradeFit,
                reason: reason(for: kind),
                gradeNote: note
            )
        }

        return scored
            .sorted {
                $0.score != $1.score ? $0.score > $1.score : $0.route.scannedAt > $1.route.scannedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    /// A soft preference, never a filter. An unreadable grade is neutral rather
    /// than disqualifying, because plenty of tags do not get read.
    private static func gradeScore(route: Route, ceiling: Grade?,
                                   kind: LeakKind) -> (Double, String?) {
        guard let ceiling, let grade = Grade.parse(route.grade),
              let steps = grade.steps(from: ceiling) else { return (0.5, nil) }

        if wantsEasier(kind) {
            // Best a little below the ceiling, worse the further either way.
            let score: Double
            switch steps {
            case ..<(-9):   score = 0.4        // so easy it teaches nothing
            case (-9)...(-1): score = 1.0
            case 0:         score = 0.6
            default:        score = 0.2        // above your limit, so the drill fails
            }
            return (score, steps < 0 ? "below your hardest send" :
                           steps == 0 ? "at your hardest send" : "above your hardest send")
        }

        let score = steps <= 0 ? 1.0 : (steps <= 3 ? 0.7 : 0.3)
        return (score, steps < 0 ? "below your hardest send" :
                       steps == 0 ? "at your hardest send" : "above your hardest send")
    }
}
