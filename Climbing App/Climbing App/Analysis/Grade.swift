import Foundation

/// A grade read off a tag, turned into something orderable.
///
/// Only grades on the same scale are ever compared. A V4 is not a 5.11a in any
/// way the app is entitled to assert, and gyms that use both are common, so
/// cross-scale comparison is simply refused rather than fudged with a conversion
/// table that would be wrong for half of them.
struct Grade: Equatable {
    enum Scale: String { case vScale, yds, french }

    let scale: Scale
    /// Ordering only. The absolute value means nothing outside its own scale.
    let index: Int

    static func parse(_ text: String) -> Grade? {
        let s = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !s.isEmpty else { return nil }

        // V scale: VB, V0 through V17, with an optional plus or minus.
        if s.hasPrefix("V") {
            let rest = s.dropFirst()
            if rest.hasPrefix("B") { return Grade(scale: .vScale, index: 0) }
            let digits = rest.prefix { $0.isNumber }
            if let n = Int(digits), n <= 17 {
                var index = (n + 1) * 3
                if rest.contains("+") { index += 1 }
                if rest.contains("-") { index -= 1 }
                return Grade(scale: .vScale, index: index)
            }
            return nil
        }

        // Yosemite: 5.6 through 5.15d.
        if s.hasPrefix("5.") {
            let rest = s.dropFirst(2)
            let digits = rest.prefix { $0.isNumber }
            guard let major = Int(digits), (0...15).contains(major) else { return nil }
            let letter = rest.drop { $0.isNumber }.first
            let offset = letterOffset(letter)
            return Grade(scale: .yds, index: major * 4 + offset)
        }

        // French sport: 4a through 9c, with an optional plus.
        if let first = s.first, let major = Int(String(first)), (4...9).contains(major) {
            let rest = s.dropFirst()
            guard let letter = rest.first, "ABC".contains(letter) else { return nil }
            let offset = letterOffset(letter)
            return Grade(scale: .french, index: major * 8 + offset * 2 + (rest.contains("+") ? 1 : 0))
        }

        return nil
    }

    private static func letterOffset(_ c: Character?) -> Int {
        switch c {
        case "A": return 0
        case "B": return 1
        case "C": return 2
        case "D": return 3
        default:  return 0
        }
    }

    /// How this grade sits against another, or nil when they are not comparable.
    func steps(from other: Grade) -> Int? {
        guard scale == other.scale else { return nil }
        return index - other.index
    }
}
