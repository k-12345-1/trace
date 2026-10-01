import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClimbingApp

private final class HoldToken {}

/// What a hold looks like, roughly, and how the climber's answer moves it.
@Suite("Hold shapes")
struct HoldShapeTests {
    typealias F = HoldShapeEngine.Features
    typealias H = ClimbNotes.HoldType

    @Test func theDefaultsGuessWhatAClimberWould() {
        let p = HoldShapeEngine.defaultPrototypes
        #expect(HoldShapeEngine.classify(F(size: 1.0, stretch: 0.0, lip: 0.0, fill: 0.8), prototypes: p) == .slopers)
        #expect(HoldShapeEngine.classify(F(size: 0.7, stretch: 0.2, lip: 0.4, fill: 0.6), prototypes: p) == .jugs)
        #expect(HoldShapeEngine.classify(F(size: -1.0, stretch: 0.6, lip: 0.1, fill: 0.7), prototypes: p) == .crimps)
        #expect(HoldShapeEngine.classify(F(size: 0.0, stretch: -0.7, lip: 0.1, fill: 0.6), prototypes: p) == .pinches)
    }

    @Test func theSentenceSaysMostlyAndSome() {
        let g = HoldShapeEngine.Guess(counts: [.crimps: 7, .slopers: 3])
        #expect(g.sentence == "Mostly crimps, some slopers")
        #expect(g.suggested == [.crimps, .slopers])
        #expect(HoldShapeEngine.Guess(counts: [:]).sentence == nil)
        #expect(HoldShapeEngine.Guess(counts: [.jugs: 4, .crimps: 3, .pinches: 1]).suggested == [.jugs, .crimps])
    }

    /// The defect this exists for: a climber who keeps saying "jugs" where the
    /// guess said "slopers" moves the guess until it agrees.
    @Test func correctionsMoveTheGuess() {
        var p = HoldShapeEngine.defaultPrototypes
        let big = F(size: 1.0, stretch: 0.0, lip: 0.05, fill: 0.8)   // a sloper by default
        #expect(HoldShapeEngine.classify(big, prototypes: p) == .slopers)
        for _ in 0..<12 {
            HoldShapeEngine.learn(from: [big, big, big], chosen: [.jugs], prototypes: &p)
        }
        #expect(HoldShapeEngine.classify(big, prototypes: p) == .jugs)
    }

    @Test func agreementDoesNotChangeTheAnswer() {
        var p = HoldShapeEngine.defaultPrototypes
        let crimp = F(size: -1.0, stretch: 0.6, lip: 0.1, fill: 0.7)
        HoldShapeEngine.learn(from: [crimp], chosen: [.crimps], prototypes: &p)
        #expect(HoldShapeEngine.classify(crimp, prototypes: p) == .crimps)
        #expect(p[.crimps]!.distance(to: crimp) < HoldShapeEngine.defaultPrototypes[.crimps]!.distance(to: crimp))
    }

    /// Two types named at once says nothing about which hold was which, so
    /// nothing is pulled, only the wrong guess pushed.
    @Test func twoNamedTypesOnlyPush() {
        var p = HoldShapeEngine.defaultPrototypes
        let big = F(size: 1.0, stretch: 0.0, lip: 0.05, fill: 0.8)
        HoldShapeEngine.learn(from: [big], chosen: [.jugs, .crimps], prototypes: &p)
        #expect(p[.jugs] == HoldShapeEngine.defaultPrototypes[.jugs])
        #expect(p[.crimps] == HoldShapeEngine.defaultPrototypes[.crimps])
        #expect(p[.slopers] != HoldShapeEngine.defaultPrototypes[.slopers])
    }

    @Test func pocketsAndVolumesAreNeverGuessed() {
        var p = HoldShapeEngine.defaultPrototypes
        HoldShapeEngine.learn(from: [F(size: 0, stretch: 0, lip: 0, fill: 0.5)], chosen: [.pockets], prototypes: &p)
        #expect(!HoldShapeEngine.guessable.contains(.pockets))
        #expect(!HoldShapeEngine.guessable.contains(.volumes))
    }

    /// On the real wall, every green hold measures, and the big green blobs do
    /// not come back as crimps.
    @Test func theRealWallMeasures() throws {
        let url = try #require(Bundle(for: HoldToken.self).url(forResource: "wall2", withExtension: "jpg"))
        let image = try #require(UIImage(data: Data(contentsOf: url))?.cgImage)
        let green = Lab(r: 0x30, g: 0x4B, b: 0x2B)
        let holds = RouteScanner.detectHolds(in: image, color: green).map(\.rect)
        #expect(holds.count >= 3)
        let features = HoldShapeEngine.features(of: holds, colour: green, in: image)
        #expect(features.compactMap { $0 }.count == holds.count)
        let guess = HoldShapeEngine.guess(features, prototypes: HoldShapeEngine.defaultPrototypes)
        #expect(guess.total == holds.count)
        let byArea = zip(holds, features).sorted { $0.0.width * $0.0.height < $1.0.width * $1.0.height }
        #expect(HoldShapeEngine.classify(byArea.last!.1!, prototypes: HoldShapeEngine.defaultPrototypes) != .crimps)
        #expect(HoldShapeEngine.classify(byArea.first!.1!, prototypes: HoldShapeEngine.defaultPrototypes) == .crimps)
        #expect(guess.sentence != nil)
    }

    @Test func prototypesRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(HoldShapeEngine.defaultPrototypes)
        let back = try JSONDecoder().decode([H: F].self, from: data)
        #expect(back == HoldShapeEngine.defaultPrototypes)
    }
}
