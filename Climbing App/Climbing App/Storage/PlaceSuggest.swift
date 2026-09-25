import Foundation
import MapKit

/// Guesses the place you are typing.
///
/// This is MapKit's own completer, which is the same thing Maps uses and needs
/// no key and no account. It runs against Apple's service, so unlike everything
/// else in Trace the few characters typed here do leave the phone. That is worth
/// knowing and it is why this exists only on the one field where it earns its
/// keep, and why it is never handed anything but what was typed into that field.
///
/// Results are cut down to a place rather than an address. "Boulder, CO" is the
/// answer to where you climb; 1755 29th Street is not.
@MainActor
final class PlaceSuggest: NSObject, ObservableObject {

    @Published private(set) var results: [String] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Addresses only. The point-of-interest set would offer every climbing
        // gym in the country as an answer to which city you are in.
        completer.resultTypes = [.address]
    }

    /// Ask, or clear. A query of fewer than two characters matches most of the
    /// world, so it is not worth asking about.
    func suggest(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() { results = [] }

    /// "Boulder, CO, United States" becomes "Boulder, CO".
    ///
    /// The completer returns a title and a subtitle, and for an address the
    /// state usually sits in the subtitle. Both are joined and then trimmed back
    /// to the first two parts, which is city and state everywhere in the US and
    /// the closest thing to it elsewhere.
    nonisolated static func shorten(title: String, subtitle: String) -> String? {
        let joined = subtitle.isEmpty ? title : "\(title), \(subtitle)"
        let parts = joined
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "United States" && $0 != "USA" }
        guard !parts.isEmpty else { return nil }
        return parts.prefix(2).joined(separator: ", ")
    }
}

extension PlaceSuggest: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let shortened = completer.results.compactMap {
            Self.shorten(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in
            // Duplicates are common once an address is trimmed back to its city,
            // because five streets in Boulder all shorten to Boulder.
            var seen = Set<String>()
            self.results = shortened.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
