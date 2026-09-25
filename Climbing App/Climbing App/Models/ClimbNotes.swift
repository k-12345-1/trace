import Foundation

/// What the climber says about a climb.
///
/// Everything else in Trace is read off the footage, which means everything
/// else in Trace is the outside of the climb. Whether it felt desperate or
/// casual, whether the holds were slick or positive, why a foot cut: none of
/// that is in the pixels, and all of it is the reason somebody remembers a
/// route. Two scales and a line, which is enough to be worth filling in between
/// burns and little enough that it gets filled in at all.
///
/// Every field is optional and the whole thing is optional on a climb, so a
/// climb nobody said anything about is not a climb full of zeroes.
struct ClimbNotes: Codable, Equatable {

    /// A five point scale, with both ends named so a number means something.
    enum Scale: Int, Codable, CaseIterable, Identifiable {
        case one = 1, two, three, four, five
        var id: Int { rawValue }
    }

    /// How hard it felt, one easy and five at your limit.
    var effort: Int?
    /// How the holds were, one slick and five positive.
    var holds: Int?
    /// Anything the two scales do not hold.
    var note: String = ""

    var isEmpty: Bool { effort == nil && holds == nil && note.isEmpty }

    static let effortEnds = (low: "Easy", high: "At my limit")
    static let holdEnds = (low: "Slick", high: "Positive")

    /// What a number on each scale is called, because "3 out of 5" is not a
    /// memory of anything.
    static func effortLabel(_ value: Int) -> String {
        switch value {
        case 1:  return "Easy"
        case 2:  return "Comfortable"
        case 3:  return "Working for it"
        case 4:  return "Hard"
        default: return "At my limit"
        }
    }

    static func holdLabel(_ value: Int) -> String {
        switch value {
        case 1:  return "Slick"
        case 2:  return "Poor"
        case 3:  return "Fair"
        case 4:  return "Good"
        default: return "Positive"
        }
    }
}
