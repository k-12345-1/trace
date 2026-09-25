import Foundation
import CoreGraphics

/// What to do differently, read off the body in the seconds before it came off.
///
/// ## What this is, and what it is not
///
/// This is not beta. Trace has never seen the route: the video shows a person
/// against a wall, and nothing in it says where the holds were, which ones were
/// on, which way they faced, or which one you were reaching for. Anything that
/// named a hold would be invented.
///
/// What it can do is read the body, which is the half it can actually see. At
/// the moment you came off, your weight was somewhere relative to your hands
/// and feet, your arms were at some angle, your hips were some distance from
/// the line of your feet, and you were moving at some speed. Each of those has
/// a correction that is true regardless of what the route was, and each one
/// here is quoted with the number it came from.
///
/// So: movement, not sequence. "A flag out to the right" rather than "use the
/// left crimp".
enum FallAdvice {

    /// One thing to try, and the measurement behind it.
    struct Suggestion: Identifiable {
        /// The correction, in the words a coach would use.
        let move: String
        /// The reading that produced it, so nothing here is a hunch.
        let because: String
        /// Rough ordering, worst first.
        let weight: Double

        var id: String { move }
    }

    /// How far back to look. A fall is the end of something that started before
    /// it, and two seconds is about one move.
    static let window = 2.0

    // MARK: Thresholds, all in the units the metrics already use.

    static let swungOut = 0.3          // torso lengths outside the contacts
    static let bentElbow = 145.0       // degrees
    static let hipsOut = 0.45          // torso lengths sideways of the feet
    static let rushing = 1.4           // torso lengths a second

    static func suggestions(frames: [PoseFrame], fellAt: Double) -> [Suggestion] {
        let before = frames.filter { $0.time >= fellAt - window && $0.time <= fellAt }
        guard !before.isEmpty,
              let torso = MetricsEngine.medianTorso(before), torso > 0.01
        else { return [] }

        var out: [Suggestion] = []

        // 1. Weight outside the contacts. The missing second force.
        if let worst = before.max(by: { (ForceEngine.overhang($0) ?? 0) < (ForceEngine.overhang($1) ?? 0) }),
           let over = ForceEngine.overhang(worst), over > swungOut,
           let com = worst.com {
            let xs = ForceEngine.contacts(worst).map(\.point.x)
            let toTheLeft = com.x < (xs.min() ?? com.x)
            let away = toTheLeft ? "right" : "left"
            let toward = toTheLeft ? "left" : "right"
            out.append(Suggestion(
                move: "Flag a foot out to the \(away), or find one on the \(toward)",
                because: String(format: "Your weight was %.1f torso lengths %@ of every hand and foot you had on. Nothing was pushing back on the other side, so it turned into a swing.", over, toward == "left" ? "left" : "right"),
                weight: 3 + over))
        }

        // 2. Arms bent while holding position.
        if let mean = MetricsEngine.meanElbow(frames: before), mean < bentElbow {
            out.append(Suggestion(
                move: "Straighten your arms before the reach, not during it",
                because: "Your elbows averaged \(Int(mean.rounded())) degrees in the two seconds before you came off. A bent arm is your bicep holding you up, and it is on a clock.",
                weight: 2 + (bentElbow - mean) / 40))
        }

        // 3. Hips out from the line of the feet.
        let offset = MetricsEngine.comOffsetFromFeet(frames: before,
                                                     times: before.map(\.time))
        if offset > hipsOut {
            out.append(Suggestion(
                move: "Turn a hip into the wall and get your weight back over your feet",
                because: String(format: "Your center of mass sat %.2f torso lengths to the side of your feet. Your fingers were holding the difference.", offset),
                weight: 1.5 + offset))
        }

        // 4. Arriving fast.
        let speeds = MetricsEngine.speedSeries(path: before.compactMap(\.com),
                                               times: before.compactMap { $0.com != nil ? $0.time : nil })
        if let peak = speeds.max(), peak / torso > rushing {
            out.append(Suggestion(
                move: "Slow the move down and take it in one steady pull",
                because: String(format: "You were moving at %.1f torso lengths a second going into it. Starting and stopping spikes the force on the hold well past your own weight.", peak / torso),
                weight: 1 + peak / torso / 2))
        }

        return out.sorted { $0.weight > $1.weight }
    }

    /// The honest caveat, said wherever the suggestions are shown.
    static let caveat = "These are about your body, not about the route. Trace has never seen the wall you were on, so it will not tell you which hold to use."
}
