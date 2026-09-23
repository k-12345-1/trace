import Foundation

/// One route in your library: everything you have recorded under the same name.
///
/// Trace never knows what a route is. It knows what you called a climb, and that
/// two climbs you called the same thing are the same route. That is the whole
/// mechanism, and it is why the library works in a gym nobody has ever scanned.
struct LibraryEntry: Identifiable {
    let attempts: [Climb]

    var id: String { latest.id.uuidString }

    /// Newest first, which is the order the library reads in.
    var latest: Climb { attempts.max(by: { $0.recordedAt < $1.recordedAt }) ?? attempts[0] }

    var name: String {
        let trimmed = latest.label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled climb" : trimmed
    }

    var attemptCount: Int { attempts.count }
    var sendCount: Int { attempts.filter { $0.isSent }.count }
    var lastClimbed: Date { latest.recordedAt }

    /// The worst thing Trace found across the attempts, which is what the card
    /// should show: a route you have half-fixed still has the leak.
    var topFinding: Finding? {
        attempts.compactMap { $0.findings.first }
            .max(by: { $0.severity.rawValue < $1.severity.rawValue })
    }

    /// Only trustworthy attempts carry numbers worth putting on a card.
    var measured: [Climb] { attempts.filter { $0.metrics.isTrustworthy } }
}
