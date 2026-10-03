import Testing
import Foundation
import UIKit
@testable import ClimbingApp

private final class StanceToken {}

/// The planner's figure, measured the way real climbers were.
///
/// Three clips of real bouldering, forty-seven, forty-two and twenty-five
/// seconds, were tracked with Vision on the Mac and measured in torso
/// lengths, the torso being the shoulders' midpoint to the hips'. Over
/// the frames where the climber was still:
///
///     hips below the top hand        median 1.04   quartiles 0.37 to 1.47
///     top hand above the shoulders   median 0.18   quartiles -0.30 to 0.60
///     foot below the hips            median 1.35   quartiles 0.92 to 1.76
///     knee angle                     median 155    quartiles 133 to 168
///     elbow angle                    median 147    quartiles 125 to 165
///     feet apart                     median 2.40   quartiles 1.64 to 2.81
///     torso lean                     median 31     quartiles 14 to 60
///
/// Measured the same way, the planner used to draw a sitting hang: hips
/// 1.82 under the top hand, knees at 95 degrees, feet 0.87 under the
/// hips, and no lean at all. These tests hold the planner's medians over
/// every route the scanner finds on the six real walls inside the real
/// climbers' quartiles. The elbow is not held, because a drawn arm cannot
/// be foreshortened the way a real one reaching to the wall is; its fold
/// is capped instead.
@Suite("Stance statistics", .serialized)
struct StanceStatsTests {
    static func sequences() throws -> [(String, String, BetaEngine.Sequence, LineEngine.Line)] {
        var out: [(String, String, BetaEngine.Sequence, LineEngine.Line)] = []
        for name in ["gymwall", "wall2", "wall3", "wall4", "wall5", "wall6"] {
            let url = try #require(Bundle(for: StanceToken.self).url(forResource: name, withExtension: "jpg"))
            let image = try #require(UIImage(data: Data(contentsOf: url))?.upright.cgImage)
            let bmp = try #require(Bitmap(image, targetWidth: RouteScanner.workingWidth))
            let r = FaceEngine.read(in: bmp)
            let mid = Double(bmp.width) / 2, h = Double(bmp.height)
            let top = r.top?.y(atX: mid).map { max(0, $0 / h) } ?? 0
            let floor = r.floor?.y(atX: mid).map { min(1, $0 / h) } ?? 1
            for s in RouteScanner.onTheWall(RouteScanner.palette(in: image), reading: r, width: bmp.width, height: bmp.height) {
                guard let line = LineEngine.read(holds: s.holds.map(\.rect)) else { continue }
                let began = Date()
                guard let seq = BetaEngine.read(line: line, shape: .average, wallHeight: floor - top,
                                                mat: r.floor == nil ? nil : floor) else { continue }
                // The feet never start on the mat, nor land on it later.
                if r.floor != nil {
                    for p in seq.stances {
                        #expect(max(p.leftFoot.y, p.rightFoot.y) <= floor - BetaEngine.matClearance + 1e-6,
                                "\(name) \(s.hex): a foot on the mat")
                    }
                }
                // Planned on the phone while the page waits.
                #expect(Date().timeIntervalSince(began) < 2, "\(name) \(s.hex) took too long to plan")
                out.append((name, s.hex, seq, line))
            }
        }
        return out
    }

    static func angle(at c: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let v1 = (Double(a.x - c.x), Double(a.y - c.y)), v2 = (Double(b.x - c.x), Double(b.y - c.y))
        let dot: Double = v1.0 * v2.0 + v1.1 * v2.1
        let n: Double = hypot(v1.0, v1.1) * hypot(v2.0, v2.1) + 1e-9
        let ratio: Double = max(-1, min(1, dot / n))
        return Foundation.acos(ratio) * 180 / Double.pi
    }
    static func d(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }

    /// The measures, in torso units, for one stance.
    static func measures(_ p: BetaEngine.Pose) -> [String: [Double]] {
        let sh = CGPoint(x: (p.leftShoulder.x + p.rightShoulder.x) / 2, y: (p.leftShoulder.y + p.rightShoulder.y) / 2)
        let torso = d(sh, p.hips)
        var m: [String: [Double]] = [:]
        func add(_ k: String, _ v: Double) { m[k, default: []].append(v) }
        add("elbow angle", angle(at: p.leftElbow, p.leftShoulder, p.leftHand))
        add("elbow angle", angle(at: p.rightElbow, p.rightShoulder, p.rightHand))
        add("knee angle", angle(at: p.leftKnee, p.hips, p.leftFoot))
        add("knee angle", angle(at: p.rightKnee, p.hips, p.rightFoot))
        let top = min(p.leftHand.y, p.rightHand.y)
        add("hips below top hand / torso", (p.hips.y - top) / torso)
        add("top hand above shoulders / torso", (sh.y - top) / torso)
        add("hand spread / torso", d(p.leftHand, p.rightHand) / torso)
        for f in [p.leftFoot, p.rightFoot] { add("foot below hips / torso", (f.y - p.hips.y) / torso) }
        add("foot spread / torso", d(p.leftFoot, p.rightFoot) / torso)
        add("hips sideways off feet mid / torso", abs(p.hips.x - (p.leftFoot.x + p.rightFoot.x) / 2) / torso)
        add("top hand to lowest foot / torso", (max(p.leftFoot.y, p.rightFoot.y) - top) / torso)
        add("smeared feet", Double((p.leftFootHold == nil ? 1 : 0) + (p.rightFootHold == nil ? 1 : 0)))
        add("torso lean deg", Double(atan2(abs(sh.x - p.hips.x), max(1e-6, p.hips.y - sh.y))) * 180 / Double.pi)
        return m
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.isEmpty ? .nan : s[s.count / 2]
    }

    static func summary(_ xs: [Double]) -> String {
        let s = xs.sorted()
        func q(_ p: Double) -> Double { s[Int(p * Double(s.count - 1))] }
        return String(format: "n=%4d  p10=%6.2f p25=%6.2f med=%6.2f p75=%6.2f p90=%6.2f", s.count, q(0.1), q(0.25), q(0.5), q(0.75), q(0.9))
    }

    @Test("The planner's figure stands the way real climbers stand")
    func plannerStandsLikeAClimber() throws {
        var all: [String: [Double]] = [:]
        var stances = 0
        for (_, _, seq, _) in try Self.sequences() {
            for p in seq.stances {
                stances += 1
                for (k, v) in Self.measures(p) { all[k, default: []].append(contentsOf: v) }
            }
        }
        #expect(stances > 300)
        for k in all.keys.sorted() { print("STAT \(k.padding(toLength: 36, withPad: " ", startingAt: 0)) \(Self.summary(all[k]!))") }

        func med(_ k: String) -> Double { Self.median(all[k] ?? []) }
        // Standing, not a sitting hang: hips about a torso under the top
        // hand, the hand about level with the shoulders.
        #expect((0.8...1.5).contains(med("hips below top hand / torso")), "\(med("hips below top hand / torso"))")
        #expect((-0.3...0.6).contains(med("top hand above shoulders / torso")), "\(med("top hand above shoulders / torso"))")
        // Legs nearly straight at rest, feet a leg below the hips.
        #expect(med("knee angle") >= 133, "\(med("knee angle"))")
        #expect(med("foot below hips / torso") >= 1.1, "\(med("foot below hips / torso"))")
        // Hands to feet about as far as a real climber spans.
        #expect((2.3...3.3).contains(med("top hand to lowest foot / torso")), "\(med("top hand to lowest foot / torso"))")
        // Most stances have both feet on holds.
        #expect(med("smeared feet") == 0, "\(med("smeared feet"))")
        // A drawn joint never folds past its cap.
        #expect((all["elbow angle"] ?? []).min() ?? 0 >= BetaEngine.tightestElbow - 1)
        #expect((all["knee angle"] ?? []).min() ?? 0 >= BetaEngine.tightestKnee - 1)
    }
}
