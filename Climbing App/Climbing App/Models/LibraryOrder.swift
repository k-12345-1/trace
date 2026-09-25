import Foundation

/// How the library is arranged.
///
/// Three questions you might be asking of a list of routes, rather than three
/// ways of shuffling it. What have I been on lately, which of these did I climb
/// well, and which ones have I actually sent. Each one reverses, because both
/// ends of every one of them is a real question: the worst-climbed routes are
/// what to work on, and the best-climbed ones are what worked.
enum LibraryOrder: String, CaseIterable, Identifiable {
    case recent, efficiency, sent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent:     return "Recent"
        case .efficiency: return "Efficiency"
        case .sent:       return "Sent"
        }
    }

    /// What the top of the list holds, said out loud, because an arrow on a
    /// chip is not self-explanatory and a sort nobody can read is a sort
    /// nobody trusts.
    func heading(reversed: Bool) -> String {
        switch self {
        case .recent:     return reversed ? "Oldest first" : "Newest first"
        case .efficiency: return reversed ? "Worst climbed first" : "Best climbed first"
        case .sent:       return reversed ? "Unsent first" : "Sent first"
        }
    }

    /// The library, arranged.
    ///
    /// `cost` is how much a route wasted, from zero to one, and nil for a route
    /// Trace could not measure. It is handed in rather than computed here so
    /// this stays a pure function of its inputs, and so the screen can hand in
    /// a cached reading instead of re-running the analysis on every redraw.
    ///
    /// Anything unmeasured sinks to the bottom in both directions. Reversing
    /// the order is asking for the other end of the same question, and "we
    /// could not tell" is not an answer at either end of it.
    static func sort(_ entries: [LibraryEntry], by order: LibraryOrder,
                     reversed: Bool, cost: (LibraryEntry) -> Double?) -> [LibraryEntry] {
        switch order {
        case .recent:
            return entries.sorted {
                $0.lastClimbed == $1.lastClimbed
                    ? tieBreak($0, $1)
                    : (reversed ? $0.lastClimbed < $1.lastClimbed
                                : $0.lastClimbed > $1.lastClimbed)
            }

        case .efficiency:
            let keyed = entries.map { (entry: $0, cost: cost($0)) }
            let measured = keyed.filter { $0.cost != nil }.sorted {
                $0.cost! == $1.cost!
                    ? tieBreak($0.entry, $1.entry)
                    : (reversed ? $0.cost! > $1.cost! : $0.cost! < $1.cost!)
            }
            let rest = keyed.filter { $0.cost == nil }
                .sorted { tieBreak($0.entry, $1.entry) }
            return (measured + rest).map(\.entry)

        case .sent:
            return entries.sorted {
                let a = $0.sendCount > 0, b = $1.sendCount > 0
                if a != b { return reversed ? b : a }
                if $0.lastClimbed != $1.lastClimbed { return $0.lastClimbed > $1.lastClimbed }
                return tieBreak($0, $1)
            }
        }
    }

    /// Name, then id. Without a total order the grid reshuffles every time the
    /// view recomputes, which reads as the list glitching.
    private static func tieBreak(_ a: LibraryEntry, _ b: LibraryEntry) -> Bool {
        a.name == b.name ? a.id < b.id : a.name < b.name
    }
}
