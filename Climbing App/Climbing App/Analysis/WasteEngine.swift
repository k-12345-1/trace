import Foundation
import CoreGraphics

/// The movement that did not get you anywhere.
///
/// Entropy and path ratio already say *how much* of a climb was wasted, as one
/// number each for the whole thing. Neither says *when*, and a number you
/// cannot point at is hard to act on. This finds the individual excursions: the
/// spans where your center of mass left a position, traveled, and came back to
/// within touching distance of where it started.
///
/// A round trip is the honest definition of wasted movement, because the work
/// of getting somewhere and the work of coming back are both real and the net
/// result is nothing. It also catches the things climbers actually do: reaching
/// for a hold and taking the hand back, dropping down to reset, swaying about
/// while deciding, riding out a swing.
///
/// What it deliberately does not call waste: a pause. Standing still costs
/// forearm strength and the hesitation finding already covers it, but it is not
/// movement and it is not measured here. And nothing here is beta. A round trip
/// may have been the only way to do the move; Trace says what it cost, not that
/// you were wrong.
enum WasteEngine {

    /// Back within this many torso lengths of where it started, and the
    /// excursion has returned rather than gone somewhere.
    static let returnRadius = 0.35
    /// Below this much travel it is tracker noise and small adjustments, not a
    /// trip worth naming.
    static let minimumTravel = 0.8
    /// And it has to have actually gone somewhere first.
    ///
    /// Without this, tracker jitter is waste: a still body wobbling by a
    /// fortieth of a torso length, thirty times a second, accumulates several
    /// torso lengths of "travel" over a few seconds and returns to where it
    /// started every other frame. Requiring the excursion to reach half a torso
    /// length from its start is what tells a round trip from a noise floor.
    static let minimumAmplitude = 0.5
    /// No excursion is allowed to run longer than this, so one long climb does
    /// not collapse into a single "round trip".
    static let maximumSeconds = 8.0

    struct Excursion: Identifiable {
        /// When the body left the place it comes back to, rather than when the
        /// detector started watching.
        let start: Double
        let end: Double
        /// How far the center of mass traveled over it, in torso lengths, all of
        /// which came to nothing.
        ///
        /// Measured from the moment it left the return neighborhood, so the
        /// first fraction of a torso length of the departure is not counted.
        /// That understates a trip slightly and never overstates one, which is
        /// the right way round for a number being shown to someone as a cost.
        let travel: Double

        var id: Double { start }
        var duration: Double { max(0, end - start) }
    }

    struct Reading {
        let excursions: [Excursion]
        /// Every wasted torso length added up.
        let wasted: Double
        /// Everything traveled, wasted or not.
        let total: Double

        var share: Double { total > 0 ? wasted / total : 0 }
        var isEmpty: Bool { excursions.isEmpty }
        var worst: Excursion? { excursions.max { $0.travel < $1.travel } }
    }

    static func read(frames: [PoseFrame]) -> Reading? {
        let usable = frames.filter { $0.com != nil }
        guard usable.count >= 8,
              let torso = MetricsEngine.medianTorso(usable), torso > 0.01
        else { return nil }

        let path = usable.map { $0.com! }
        let times = usable.map(\.time)

        // Cumulative distance, so the travel over any span is one subtraction.
        var cumulative: [Double] = [0]
        for i in 1..<path.count {
            let dx = path[i].x - path[i - 1].x
            let dy = path[i].y - path[i - 1].y
            cumulative.append(cumulative[i - 1] + (dx * dx + dy * dy).squareRoot() / torso)
        }

        func away(_ a: Int, _ b: Int) -> Double {
            let dx = path[b].x - path[a].x, dy = path[b].y - path[a].y
            return (dx * dx + dy * dy).squareRoot() / torso
        }

        var out: [Excursion] = []
        var i = 0
        while i < path.count - 1 {
            // Walk forward until the body has genuinely left this point and
            // then come back to it. The first return after leaving, not the
            // furthest: the furthest swallows the approach and the departure
            // either side and reports a trip that started before it did.
            var reached = 0.0
            var end: Int?
            var j = i + 1
            while j < path.count, times[j] - times[i] <= maximumSeconds {
                let d = away(i, j)
                reached = max(reached, d)
                if reached >= minimumAmplitude && d < returnRadius { end = j; break }
                j += 1
            }
            guard let end else { i += 1; continue }

            // Trim the approach off the front.
            //
            // The walk above starts wherever it happens to be standing, and
            // anything within the return radius of the finish qualifies, so a
            // trip can be reported as beginning several frames before the body
            // actually left. The excursion proper starts at the last moment it
            // was still at the place it comes back to.
            let peak = (i...end).max { away($0, end) < away($1, end) } ?? i
            var start = i
            for s in i...peak where away(s, end) < returnRadius { start = s }

            // The amplitude is how far the body got from the place it comes
            // back to, not how far it got from the trimmed start. Measuring it
            // from the start is circular: trimming moves the start outward
            // along the departure, which shrinks the very number that decides
            // whether the departure counted.
            let travel = cumulative[end] - cumulative[start]
            if travel >= minimumTravel && away(peak, end) >= minimumAmplitude {
                out.append(Excursion(start: times[start], end: times[end], travel: travel))
                i = end                     // carry on from where it got back to
            } else {
                i += 1
            }
        }

        return Reading(excursions: out,
                       wasted: out.reduce(0) { $0 + $1.travel },
                       total: cumulative.last ?? 0)
    }

    /// The reading in one sentence, or nil when there is nothing worth saying.
    static func summary(_ r: Reading) -> String? {
        guard !r.isEmpty, r.wasted > 0 else { return nil }
        let trips = r.excursions.count
        let percent = Int((r.share * 100).rounded())
        return String(format: "%d round trip%@ that ended where %@ started, %.1f body lengths of movement in total. That is about %d percent of everything you traveled.",
                      trips, trips == 1 ? "" : "s", trips == 1 ? "it" : "they",
                      r.wasted / 2, percent)
    }

    static let caveat = "A round trip is not necessarily a mistake: sometimes it is the only way to do the move. This says what it cost, not that you were wrong."
}
