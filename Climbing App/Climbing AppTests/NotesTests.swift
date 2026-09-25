import Testing
import Foundation
@testable import ClimbingApp

/// What the climber says about a climb.
///
/// The scales are optional all the way down, and these tests are mostly about
/// that: an answer nobody gave has to stay ungiven. A three out of five on a
/// scale nobody touched is a lie the app told itself, and it would then be
/// averaged, sorted and shown back as if somebody had meant it.
@Suite("Climb notes")
struct NotesTests {

    @Test("Saying nothing is nothing")
    func silenceIsEmpty() {
        #expect(ClimbNotes().isEmpty)
        #expect(ClimbNotes(effort: 3).isEmpty == false)
        #expect(ClimbNotes(holds: 1).isEmpty == false)
        #expect(ClimbNotes(note: "slopers").isEmpty == false)
    }

    /// The trap this project has already been caught by once: Swift's
    /// synthesized decoder throws on a missing key for a non-optional property,
    /// so a climb stored before this existed has to decode through an optional.
    @Test("A climb saved before notes existed still opens")
    func oldClimbsStillDecode() throws {
        let climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(climb)) as? [String: Any])
        object.removeValue(forKey: "notes")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: object)
        let reopened = try decoder.decode(Climb.self, from: data)
        #expect(reopened.notes == nil)
    }

    @Test("What was said survives a round trip")
    func notesRoundTrip() throws {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.notes = ClimbNotes(effort: 5, holds: 2, note: "Cut feet at the lip.")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reopened = try decoder.decode(Climb.self, from: encoder.encode(climb))
        #expect(reopened.notes == climb.notes)
    }

    // MARK: The line in a list of attempts

    @Test("The line names both scales")
    func theLineReadsBack() {
        let notes = ClimbNotes(effort: 4, holds: 5, note: "")
        #expect(NotesLine.text(notes) == "Hard · Positive holds")
    }

    /// A row must not grow an empty line, which is what an always-present
    /// summary of nothing looks like.
    @Test("Nothing said is no line at all")
    func nothingSaidIsNoLine() {
        #expect(NotesLine.text(ClimbNotes()) == nil)
    }

    /// With no scales touched, the words are the only thing there is to show.
    @Test("A note on its own stands in for the scales")
    func aBareNoteShows() {
        #expect(NotesLine.text(ClimbNotes(note: "Greasy holds")) == "Greasy holds")
    }

    /// Both ends of both scales are named. A number with no word beside it is
    /// not a memory of anything.
    @Test("Every step on both scales has a name")
    func everyStepIsNamed() {
        for step in 1...5 {
            #expect(!ClimbNotes.effortLabel(step).isEmpty)
            #expect(!ClimbNotes.holdLabel(step).isEmpty)
        }
        #expect(ClimbNotes.effortLabel(1) == ClimbNotes.effortEnds.low)
        #expect(ClimbNotes.effortLabel(5) == ClimbNotes.effortEnds.high)
        #expect(ClimbNotes.holdLabel(1) == ClimbNotes.holdEnds.low)
        #expect(ClimbNotes.holdLabel(5) == ClimbNotes.holdEnds.high)
    }
}
