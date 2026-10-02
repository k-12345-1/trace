import Foundation
import CoreGraphics

/// Whether the photograph holds the whole route.
///
/// A phone held at the bottom of a wall gets most of a boulder and not all of
/// it, and a scan of two thirds of a route is a route with the wrong crux. A
/// person standing there can tell: the holds run into the edge of the
/// picture, there is a start sticker and no finish, the line heads left and
/// leaves. This reads the same three things and says which way to move the
/// camera.
///
/// - A hold cut by the frame is the strongest sign: the route is there and
///   the picture is not.
/// - The start and finish stickers, where the setters put them and the
///   photograph can read them. A route with one and not the other continues
///   past the one it lacks: no finish, and it goes on above or wherever the
///   line is heading; no start, and it goes on below.
/// - The line itself. The last hold close to an edge, with the line pointing
///   at that edge, is a route still going.
///
/// Said as a probability, never a fact: a route can end a hand's width from
/// the edge of the picture and a sticker can be hidden behind a hold.
enum CoverageEngine {

    enum Edge: String, Codable, CaseIterable { case left, right, above, below }

    struct Coverage: Equatable {
        /// The edges the route probably continues past, empty when it looks whole.
        var continues: Set<Edge>
        var sawStart: Bool
        var sawFinish: Bool
        /// Whether any stickers were read at all, so silence is not "none".
        var tagsRead: Bool

        var looksComplete: Bool { continues.isEmpty }

        /// "Probably continues to the left. Step back or move left to get it all."
        var sentence: String? {
            guard !continues.isEmpty else { return nil }
            let order: [Edge] = [.left, .right, .above, .below]
            let names = order.filter { continues.contains($0) }.map { e -> String in
                switch e {
                case .left:  return "to the left"
                case .right: return "to the right"
                case .above: return "above"
                case .below: return "below"
                }
            }
            let list = names.count <= 1 ? names.joined()
                : names.dropLast().joined(separator: ", ") + " and " + names.last!
            return "Probably continues \(list). Step back or move the camera that way to get the whole route."
        }
    }

    /// A hold this close to the edge, in frame widths, is cut by it.
    static let cut = 0.012
    /// The last hold within this much of an edge, with the line heading there,
    /// is a route still going.
    static let nearEdge = 0.14
    /// Tighter for the top: a boulder's finish sits near the top of any
    /// photograph of it, so only a hold almost at the edge says the top is
    /// missing. The sticker, when read, settles it either way.
    static let nearTop = 0.05
    /// How far a sticker can sit from a hold and still be its sticker.
    static let tagReach = 0.07
    /// A blob smaller than this, as a share of the picture, is a sticker or
    /// a bolt hole, not a hold a sticker could belong to. The stickers are
    /// coloured, and a yellow "Finish" came back as a yellow speck that then
    /// claimed its own sticker for the yellow route.
    /// A sticker is about 0.03 by 0.02 of the picture; a hold that small
    /// never carries one.
    static let tagHold = 0.0015
    /// Setters put the sticker just under its hold. A hold has to sit above
    /// or level with the sticker to own it: blue's finish sat between the
    /// blue hold above and a green one below, nearer the green.
    static let tagBelowHold = 0.01

    /// - Parameters:
    ///   - holds: this route's holds.
    ///   - tags: every sticker read off the photograph.
    ///   - others: every other route's holds. A sticker belongs to the one
    ///     hold nearest it on the whole wall, so a start under a yellow hold
    ///     is not also the green route's start because a green hold sits
    ///     beside it.
    /// The hold a sticker belongs to, among this route's, or nil when it is
    /// another route's or nobody's. The nearest hold above or level with
    /// the sticker, big enough to be a hold, nearer than any other route's.
    static func holdIndex(for t: RouteScanner.Tag, holds: [CGRect], others: [CGRect] = []) -> Int? {
        func gap(_ h: CGRect) -> Double? {
            // The hold's top at or above the sticker: under the hold, or
            // beside it. Some gyms stick the tag to the wall next to the
            // start, level with it, and judged by the hold's centre those
            // starts matched nothing.
            guard Double(h.width * h.height) >= tagHold, h.minY <= t.point.y + tagBelowHold else { return nil }
            return max(0, hypot(h.midX - t.point.x, h.midY - t.point.y) - max(h.width, h.height) / 2)
        }
        var best: (Int, Double)?
        for (i, h) in holds.enumerated() {
            if let g = gap(h), best == nil || g < best!.1 { best = (i, g) }
        }
        guard let best, best.1 <= tagReach else { return nil }
        let theirs = others.compactMap { gap($0) }.min() ?? .infinity
        return best.1 <= theirs ? best.0 : nil
    }

    /// The holds the start stickers sit under, in this route.
    static func startHolds(holds: [CGRect], tags: [RouteScanner.Tag], others: [CGRect] = []) -> [Int] {
        tagged(.start, holds: holds, tags: tags, others: others)
    }

    /// And the finish stickers.
    static func finishHolds(holds: [CGRect], tags: [RouteScanner.Tag], others: [CGRect] = []) -> [Int] {
        tagged(.finish, holds: holds, tags: tags, others: others)
    }

    private static func tagged(_ kind: RouteScanner.Tag.Kind, holds: [CGRect], tags: [RouteScanner.Tag], others: [CGRect]) -> [Int] {
        var out: [Int] = []
        for t in tags where t.kind == kind {
            if let i = holdIndex(for: t, holds: holds, others: others), !out.contains(i) { out.append(i) }
        }
        return out
    }

    static func read(holds: [CGRect], tags: [RouteScanner.Tag] = [], others: [CGRect] = []) -> Coverage {
        var out = Coverage(continues: [], sawStart: false, sawFinish: false, tagsRead: !tags.isEmpty)
        guard !holds.isEmpty else { return out }

        // Cut by the frame.
        for h in holds {
            if h.minX <= cut { out.continues.insert(.left) }
            if h.maxX >= 1 - cut { out.continues.insert(.right) }
            if h.minY <= cut { out.continues.insert(.above) }
            if h.maxY >= 1 - cut { out.continues.insert(.below) }
        }

        // The stickers that belong to this route: those whose nearest hold on
        // the wall is one of these, and close enough to be its sticker.
        func near(_ t: RouteScanner.Tag) -> Bool { holdIndex(for: t, holds: holds, others: others) != nil }
        out.sawStart = tags.contains { $0.kind == .start && near($0) }
        out.sawFinish = tags.contains { $0.kind == .finish && near($0) }

        // Where the line is heading. Bottom to top, as the line engine reads
        // it: the last hold is the highest one.
        let ordered = holds.sorted { $0.midY > $1.midY }
        guard let first = ordered.first, let last = ordered.last else { return out }
        if ordered.count >= 2 {
            let prev = ordered[ordered.count - 2]
            let dx = last.midX - prev.midX, dy = last.midY - prev.midY
            if last.minX <= nearEdge, dx < -0.02 { out.continues.insert(.left) }
            if last.maxX >= 1 - nearEdge, dx > 0.02 { out.continues.insert(.right) }
            if last.minY <= nearTop, dy < 0 { out.continues.insert(.above) }
        }

        // Stickers seen for this route decide what the line's end means. A
        // finish on the top hold is the route ending, however close to the
        // edge; no finish anywhere, with stickers read on the wall, is a top
        // not yet in the picture.
        if out.tagsRead {
            if out.sawFinish { out.continues.remove(.above) }
            else if !out.sawStart {
                // Neither sticker near this route: the stickers belong to other
                // routes and this one says nothing either way.
            } else if last.minY <= nearEdge * 2 || out.continues.contains(.left) || out.continues.contains(.right) {
                out.continues.insert(.above)
            }
            if out.sawStart { out.continues.remove(.below) }
            else if out.sawFinish, first.maxY >= 1 - nearEdge * 2 { out.continues.insert(.below) }
        }
        return out
    }
}
