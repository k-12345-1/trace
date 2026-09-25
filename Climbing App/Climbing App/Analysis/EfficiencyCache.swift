import Foundation

/// Efficiency readings, worked out once per climb.
///
/// `EfficiencyEngine.read` walks the pose frames and runs three of the other
/// engines over them, which is fine once and wrong forty times a second. It was
/// being called straight from view bodies: every attempt row on a route
/// recomputed its grade on every redraw, and sorting a library by efficiency
/// would have done it again for every comparison.
///
/// A climb's reading cannot change. The frames and the metrics are written when
/// it is analyzed and never touched again, so the id is a safe key and there is
/// nothing to invalidate. A deleted climb leaves an entry behind; it is a
/// struct of five doubles and a handful of components, and the cache is cleared
/// wholesale rather than grown forever.
@MainActor
enum EfficiencyCache {
    private static var readings: [UUID: EfficiencyEngine.Reading?] = [:]
    /// Roughly a season of climbing before it starts again from nothing.
    private static let limit = 400

    static func read(_ climb: Climb) -> EfficiencyEngine.Reading? {
        if let hit = readings[climb.id] { return hit }
        let reading = EfficiencyEngine.read(climb)
        if readings.count >= limit { readings.removeAll() }
        readings[climb.id] = reading
        return reading
    }

    /// How much a route wasted, from its best attempt: zero is nothing wasted
    /// and one is everything. Nil when no attempt on it could be measured.
    static func cost(_ entry: LibraryEntry) -> Double? {
        entry.attempts.compactMap { read($0)?.cost }.min()
    }

    static func forgetEverything() { readings.removeAll() }
}
