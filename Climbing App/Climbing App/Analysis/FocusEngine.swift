import Foundation

/// Chooses what you work on, and decides when you are done with it.
enum FocusEngine {

    /// How many recent climbs a focus is judged on. One clip is noise.
    static let window = 3
    /// How many climbs before Spotter is willing to pick a focus at all.
    static let minimumClimbs = 2

    // MARK: The number behind each leak

    /// The single metric a focus is measured on. Some go up, some go down.
    static func value(for kind: LeakKind, in m: Metrics) -> Double {
        switch kind {
        case .bentArms:      return m.staticElbowAngle
        case .wandering:     return m.pathRatio
        case .lurchy:        return m.logJerk
        case .hesitation:    return m.duration > 0 ? m.pauseTotal / m.duration : 0
        case .impreciseFeet: return Double(m.footAdjustments)
        case .weightOnArms:  return m.comOffsetFromFeet
        case .mistimedDynamics: return m.meanDeadpointError
        }
    }

    static func higherIsBetter(_ kind: LeakKind) -> Bool {
        kind == .bentArms
    }

    /// What "fixed" looks like. Deliberately modest: a focus should be winnable
    /// in a few sessions, not be a year-long project.
    static func target(for kind: LeakKind, baseline: Double) -> Double {
        switch kind {
        case .bentArms:      return min(170, baseline + 18)      // degrees, straighter
        case .impreciseFeet: return max(1, baseline * 0.5)       // half as many resets
        case .mistimedDynamics: return max(90, baseline * 0.6)   // milliseconds off the apex
        case .weightOnArms:  return max(0.25, baseline * 0.65)   // torso lengths
        default:             return baseline * 0.8               // 20 percent less
        }
    }

    static func format(kind: LeakKind, value: Double) -> String {
        switch kind {
        case .bentArms:      return "\(Int(value.rounded()))°"
        case .impreciseFeet: return String(format: "%.1f resets", value)
        case .hesitation:    return "\(Int((value * 100).rounded()))% stopped"
        case .lurchy:        return String(format: "%.1f ldlj", value)
        case .mistimedDynamics: return "\(Int(value.rounded())) ms"
        case .weightOnArms:  return String(format: "%.2f torso", value)
        default:             return String(format: "%.2f×", value)
        }
    }

    /// Plain language for what the number means, since "1.42 ldlj" tells nobody anything.
    static func meaning(for kind: LeakKind) -> String {
        switch kind {
        case .bentArms:      return "Mean elbow angle while you are not moving. Higher is straighter."
        case .wandering:     return "How much further your hips travelled than the straight line. Lower is tidier."
        case .lurchy:        return "Smoothness of your centre of mass. Lower is more continuous."
        case .hesitation:    return "Share of each climb spent not moving. Lower means more reading from the ground."
        case .impreciseFeet: return "Foot placements you had to correct, per climb. Lower is more precise."
        case .weightOnArms:  return "How far your centre of mass sits sideways of your feet while resting, in torso lengths. Lower means your legs are carrying you."
        case .mistimedDynamics: return "How far your hand lands from the top of your arc on dynamic moves. Lower is better timed."
        }
    }

    // MARK: Picking and updating

    /// The leak that keeps coming up. Only the headline finding counts, because
    /// that is the one the climber was actually told about.
    static func suggest(from climbs: [Climb]) -> LeakKind? {
        let recent = climbs.filter { $0.metrics.isTrustworthy }.prefix(10)
        guard recent.count >= minimumClimbs else { return nil }

        var tally: [LeakKind: Int] = [:]
        for climb in recent {
            guard let top = climb.findings.first else { continue }
            tally[top.kind, default: 0] += 1
        }
        return tally.max { a, b in a.value < b.value }?.key
    }

    /// Mean of the focus metric across the most recent climbs.
    static func currentValue(for kind: LeakKind, in climbs: [Climb]) -> Double? {
        let recent = climbs.filter { $0.metrics.isTrustworthy }.prefix(window)
        guard !recent.isEmpty else { return nil }
        let vals = recent.map { value(for: kind, in: $0.metrics) }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Start a focus, or refresh the one in play. Returns nil when there is not
    /// enough tracked climbing to say anything honest.
    static func evaluate(existing: Focus?, climbs: [Climb]) -> Focus? {
        let tracked = climbs.filter { $0.metrics.isTrustworthy }
        guard tracked.count >= minimumClimbs else { return existing }

        if var focus = existing, !focus.isResolved {
            guard let latest = currentValue(for: focus.kind, in: tracked) else { return focus }
            focus.latest = latest

            let reached = higherIsBetter(focus.kind)
                ? latest >= target(for: focus.kind, baseline: focus.baseline)
                : latest <= target(for: focus.kind, baseline: focus.baseline)
            if reached { focus.resolvedAt = Date() }
            return focus
        }

        // Nothing in play, or the last one is done. Pick the next.
        guard let kind = suggest(from: tracked),
              let value = currentValue(for: kind, in: tracked) else { return existing }

        // Do not immediately re-start the focus that was just retired.
        if let existing, existing.isResolved, existing.kind == kind,
           let resolved = existing.resolvedAt,
           Date().timeIntervalSince(resolved) < 60 * 60 * 24 {
            return existing
        }

        return Focus(kind: kind, startedAt: Date(), baseline: value, latest: value)
    }

    /// The line Spotter opens a session with.
    static func greeting(for focus: Focus?) -> String {
        guard let focus else {
            return "Record a climb and Spotter will pick something for you to work on."
        }
        if focus.isResolved {
            return "\(focus.kind.title) is sorted. Climb a few more and Spotter will pick the next thing."
        }
        return "Last time we were working on \(focus.kind.title.lowercased()). Let's see where it is today."
    }
}
