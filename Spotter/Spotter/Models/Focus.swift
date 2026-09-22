import Foundation

/// The one thing you are working on.
///
/// A partner who gives you something different to work on every burn is useless,
/// so a focus persists until it measurably improves rather than until you get bored.
struct Focus: Codable, Identifiable {
    var id = UUID()
    var kind: LeakKind
    var startedAt: Date
    var baseline: Double
    var latest: Double
    var resolvedAt: Date?

    var isResolved: Bool { resolvedAt != nil }

    var daysActive: Int {
        let days = Calendar.current.dateComponents([.day], from: startedAt, to: Date()).day ?? 0
        return max(1, days + 1)
    }

    /// 0 to 1, how far from the baseline toward the target.
    var progress: Double {
        let target = FocusEngine.target(for: kind, baseline: baseline)
        let span = target - baseline
        guard abs(span) > 0.0001 else { return 1 }
        return min(max((latest - baseline) / span, 0), 1)
    }

    var readout: String {
        FocusEngine.format(kind: kind, value: latest)
    }
    var baselineReadout: String {
        FocusEngine.format(kind: kind, value: baseline)
    }
}
