import Testing
import Foundation
@testable import ClimbingApp

/// Turning MapKit's address completions into the answer to "where do you climb".
@Suite("Place suggestions")
struct PlaceTests {

    @Test func aCityAndStateSurvivesIntact() {
        #expect(PlaceSuggest.shorten(title: "Boulder", subtitle: "CO, United States")
                == "Boulder, CO")
    }

    @Test func theCountryIsDropped() {
        // It is the answer for everyone using the app and so it is noise.
        #expect(PlaceSuggest.shorten(title: "Bishop, CA", subtitle: "United States")
                == "Bishop, CA")
        #expect(PlaceSuggest.shorten(title: "Bishop, CA", subtitle: "USA")
                == "Bishop, CA")
    }

    /// A street address is not an answer to where you climb, so it is cut back
    /// to the two parts that are.
    @Test func aStreetAddressIsCutBackToItsPlace() {
        #expect(PlaceSuggest.shorten(title: "1755 29th Street",
                                     subtitle: "Boulder, CO, United States")
                == "1755 29th Street, Boulder")
    }

    @Test func aBareTitleWorks() {
        #expect(PlaceSuggest.shorten(title: "Salt Lake City", subtitle: "") == "Salt Lake City")
    }

    @Test func emptyGivesNothingRatherThanAnEmptyString() {
        #expect(PlaceSuggest.shorten(title: "", subtitle: "") == nil)
        #expect(PlaceSuggest.shorten(title: " , , ", subtitle: "") == nil)
        #expect(PlaceSuggest.shorten(title: "United States", subtitle: "") == nil)
    }

    @Test func strayWhitespaceIsTrimmed() {
        #expect(PlaceSuggest.shorten(title: "  Austin ", subtitle: " TX , United States")
                == "Austin, TX")
    }
}
