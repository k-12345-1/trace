import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

/// Directness between positions, which is what replaced the straight line.
///
/// The test that matters is `aDiagonalRouteClimbedCleanlyCostsNothing`. The old
/// measure compared the whole path against a straight line from the start of
/// the climb to the top of it, and on a boulder that line does not exist: a
/// climber who followed a zig-zag problem perfectly was told they travelled far
/// further than they needed to. That test climbs such a problem perfectly and
/// asserts both halves of the point, the new number being near zero and the old
/// one being high on the very same frames.
@Suite("Directness between moves")
struct MoveTests {

    // MARK: Building a climb

    /// A body at a point, with the fixture's 0.20 torso so distances in torso
    /// lengths mean what the engine thinks they mean.
    private func body(_ t: Double, _ p: CGPoint) -> PoseFrame {
        Fixture.body(t: t, comY: p.y, feetX: p.x,
                     wrist: CGPoint(x: p.x, y: p.y - 0.30))
    }

    /// Eased from zero to one and back to zero, so every move starts and ends
    /// slow. That is what gives the engine the boundaries it looks for, and it
    /// is also how people climb: you are slowest at each position.
    private func ease(_ u: Double) -> Double { 0.5 - 0.5 * cos(u * .pi) }

    /// Straight from one position to the next.
    private func hop(_ a: CGPoint, _ b: CGPoint, steps: Int = 24) -> [CGPoint] {
        (1...steps).map { i in
            let e = ease(Double(i) / Double(steps))
            return CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
        }
    }

    /// The same move, taken the long way: pushed out sideways and brought back.
    /// A reach that set off and corrected, in other words.
    private func bowed(_ a: CGPoint, _ b: CGPoint, by bow: Double,
                       steps: Int = 24) -> [CGPoint] {
        (1...steps).map { i in
            let u = Double(i) / Double(steps)
            let e = ease(u)
            let push = sin(u * .pi) * bow
            return CGPoint(x: a.x + (b.x - a.x) * e + push,
                           y: a.y + (b.y - a.y) * e)
        }
    }

    private func frames(_ points: [CGPoint]) -> [PoseFrame] {
        points.enumerated().map { body(Double($0.offset) / 30, $0.element) }
    }

    /// A route as a list of positions, climbed directly between them.
    private func climbed(_ stops: [CGPoint], bow: Double = 0) -> [PoseFrame] {
        var points = [stops[0]]
        for (a, b) in zip(stops, stops.dropFirst()) {
            points += bow == 0 ? hop(a, b) : bowed(a, b, by: bow)
        }
        return frames(points)
    }

    /// Straight up the middle: four positions, each above the last.
    private let ladder = [CGPoint(x: 0.5, y: 0.85), CGPoint(x: 0.5, y: 0.68),
                          CGPoint(x: 0.5, y: 0.50), CGPoint(x: 0.5, y: 0.32),
                          CGPoint(x: 0.5, y: 0.15)]

    /// A real boulder: the holds go up but they also go across, and back.
    private let zigzag = [CGPoint(x: 0.30, y: 0.85), CGPoint(x: 0.62, y: 0.70),
                          CGPoint(x: 0.28, y: 0.55), CGPoint(x: 0.66, y: 0.38),
                          CGPoint(x: 0.34, y: 0.18)]

    // MARK: What it should say

    @Test("A ladder climbed cleanly costs nothing")
    func aLadderCostsNothing() throws {
        let reading = try #require(MoveEngine.read(frames: climbed(ladder)))
        #expect(reading.moves.count >= 3)
        #expect(reading.waste < 0.05, "waste was \(reading.waste)")
    }

    /// The whole reason this engine exists.
    ///
    /// Every move here is taken in a dead straight line to the next hold. The
    /// climber did nothing wrong. The route is a zig-zag, which is the setter's
    /// doing and not theirs, and the measure has to know the difference.
    @Test("A diagonal route climbed cleanly costs nothing")
    func aDiagonalRouteClimbedCleanlyCostsNothing() throws {
        let clip = climbed(zigzag)
        let reading = try #require(MoveEngine.read(frames: clip))
        #expect(reading.waste < 0.05, "waste was \(reading.waste)")

        // And the measure this replaced, on the same frames, calls the same
        // climb a wandering mess. That gap is the bug, stated as a number.
        let old = MetricsEngine.compute(frames: clip).pathRatio
        #expect(old > 1.6, "the old path ratio was \(old), so this proves nothing")
    }

    @Test("Setting off and correcting costs something")
    func detoursCostSomething() throws {
        let clean = try #require(MoveEngine.read(frames: climbed(zigzag)))
        let wobbly = try #require(MoveEngine.read(frames: climbed(zigzag, bow: 0.11)))
        #expect(wobbly.waste > 0.10, "waste was \(wobbly.waste)")
        #expect(wobbly.waste > clean.waste + 0.08)
    }

    @Test("A worse detour costs more than a smaller one")
    func worseDetoursCostMore() throws {
        let small = try #require(MoveEngine.read(frames: climbed(zigzag, bow: 0.06)))
        let large = try #require(MoveEngine.read(frames: climbed(zigzag, bow: 0.14)))
        #expect(large.waste > small.waste)
    }

    // MARK: When it should say nothing

    @Test("Too few moves is nil, not zero")
    func tooFewMovesIsNil() {
        let stub = climbed([CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.5, y: 0.6)])
        #expect(MoveEngine.read(frames: stub) == nil)
    }

    @Test("A clip with no tracking is nil")
    func nothingTrackedIsNil() {
        #expect(MoveEngine.read(frames: []) == nil)
    }

    /// Weight shifted on the spot is not a move, and its directness is a ratio
    /// of two noise floors.
    @Test("Shuffling on one hold is not a move")
    func shufflingIsNotAMove() throws {
        var stops = ladder
        // Two extra positions a centimetre apart, in the middle of the climb.
        stops.insert(CGPoint(x: 0.505, y: 0.505), at: 3)
        stops.insert(CGPoint(x: 0.497, y: 0.499), at: 3)
        let reading = try #require(MoveEngine.read(frames: climbed(stops)))
        #expect(reading.moves.allSatisfy { $0.travelled >= 0.06 })
    }

    // MARK: The boundaries

    @Test("Both ends of the climb are positions")
    func theEndsAlwaysCount() {
        let clip = climbed(ladder)
        let path = clip.compactMap { $0.com }
        let bounds = MoveEngine.boundaries(path: path, times: clip.map(\.time))
        #expect(bounds.first == 0)
        #expect(bounds.last == path.count - 1)
    }

    /// Boundaries are local minima of the climber's own speed, not of a fixed
    /// threshold. A climber who never drops below some absolute number would
    /// otherwise make one enormous move and score as if they had wandered the
    /// whole way, which hands the smoothest climbers the worst reading.
    @Test("A fast climber still has moves")
    func speedDoesNotHideTheMoves() throws {
        // The same route twice as fast: twelve frames a move, which is four
        // tenths of a second from one hold to the next. Below about three
        // tenths the engine stops telling two positions apart and merges them,
        // which is `minimumGap` doing its job rather than failing: that is the
        // tracker's jitter, not a climber.
        var points = [zigzag[0]]
        for (a, b) in zip(zigzag, zigzag.dropFirst()) { points += hop(a, b, steps: 12) }
        let reading = try #require(MoveEngine.read(frames: frames(points)))
        #expect(reading.moves.count >= 3)
        #expect(reading.waste < 0.06, "waste was \(reading.waste)")
    }
}
