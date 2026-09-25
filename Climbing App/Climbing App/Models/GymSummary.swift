import Foundation

/// The line under a gym's name.
///
/// It exists as its own thing because it got the arithmetic wrong in a way that
/// was visible on the screen: "sent" counted scanned routes marked sent, while
/// the list underneath it showed climbs, each with a tick. A gym with three
/// ticked climbs and nothing scanned read "0 sent" under a page full of check
/// marks.
///
/// It counts what the page shows, in the order the page shows it, and it
/// mentions scanning only when something has been scanned.
enum GymSummary {

    static func line(routes: [Route], climbed: [LibraryEntry]) -> String {
        var parts: [String] = []
        if !climbed.isEmpty {
            parts.append("\(climbed.count) climb\(climbed.count == 1 ? "" : "s")")
        }
        if !routes.isEmpty { parts.append("\(routes.count) scanned") }
        if !climbed.isEmpty || !routes.isEmpty {
            parts.append("\(sent(routes: routes, climbed: climbed)) sent")
        }
        return parts.isEmpty ? "Nothing here yet" : parts.joined(separator: " · ")
    }

    /// A route sent is a route sent, whether the tick is on the scan or on the
    /// climb of it.
    ///
    /// Matched by name, which is the same rule the library already uses to
    /// decide that two clips are the same route, so scanning a problem and then
    /// filming yourself on it counts once rather than twice.
    static func sent(routes: [Route], climbed: [LibraryEntry]) -> Int {
        let sentClimbs = climbed.filter { $0.sendCount > 0 }
        let names = Set(sentClimbs.map { $0.name.lowercased() })
        let sentScans = routes.filter { $0.sent && !names.contains($0.name.lowercased()) }
        return sentClimbs.count + sentScans.count
    }
}
