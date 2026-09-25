import SwiftUI

/// Trace's mark: a ridge in outline with its shaded flank hachured.
///
/// It is an engraving rather than a logo. The silhouette carries the name, and
/// the strokes across the right flank are how a wood block or a printed map
/// shades a slope: short marks running down the fall line, long near the summit
/// and short near the foot, thinning as they go. That is where the character
/// is, and it is the one ornament in an app that otherwise has none.
///
/// Blue on white. The mark is the dark thing on a light page everywhere it
/// appears, including the app icon, which is generated from the same geometry
/// by `tools/MakeIcon.swift`. Keep the two in step.
struct MountainMark: View {
    var color: Color = Theme.blue
    /// Fraction of the frame left empty around the mark.
    var inset: Double = 0.06

    /// The ridge, in a 100 by 100 design space with y downward. A low left
    /// shoulder, a notch, a second summit, and one long flank falling right.
    static let ridge: [CGPoint] = [
        CGPoint(x: 5,  y: 84),
        CGPoint(x: 22, y: 57),
        CGPoint(x: 31, y: 65),
        CGPoint(x: 46, y: 31),
        CGPoint(x: 54, y: 43),
        CGPoint(x: 63, y: 14),
        CGPoint(x: 95, y: 84)
    ]

    /// The summit the shaded flank falls from.
    static let summit = 5

    static let outlineWeight: Double = 4.4

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let scale = (side * (1 - inset * 2)) / 100
            let ox = (size.width - 100 * scale) / 2
            let oy = (size.height - 100 * scale) / 2
            func p(_ q: CGPoint) -> CGPoint {
                CGPoint(x: ox + q.x * scale, y: oy + q.y * scale)
            }

            var body = Path()
            body.addLines(Self.ridge.map(p))
            body.closeSubpath()

            ctx.drawLayer { inner in
                inner.clip(to: body)
                var hachures = Path()
                for line in Self.hachures(count: Self.count(for: side)) {
                    hachures.move(to: p(line.from))
                    hachures.addLine(to: p(line.to))
                    // Stroked individually so each can carry its own weight.
                    inner.stroke(hachures, with: .color(color),
                                 style: StrokeStyle(lineWidth: line.weight * scale,
                                                    lineCap: .round))
                    hachures = Path()
                }
            }

            ctx.stroke(body, with: .color(color),
                       style: StrokeStyle(lineWidth: Self.outlineWeight * scale,
                                          lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    struct Hachure {
        let from: CGPoint
        let to: CGPoint
        let weight: Double
    }

    /// How many strokes to draw at a given rendered size.
    ///
    /// Twenty six of them is right on an icon and a grey smear at thirty
    /// points, so the count follows the size. The mark stays recognizable
    /// either way, which is the whole job of a mark.
    static func count(for side: Double) -> Int {
        switch side {
        case ..<26:   return 6
        case ..<44:   return 9
        case ..<90:   return 14
        case ..<200:  return 20
        default:      return 26
        }
    }

    /// The strokes across the shaded flank, in design space.
    static func hachures(count: Int) -> [Hachure] {
        guard count > 1 else { return [] }
        let a = ridge[summit], b = ridge[6]
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return [] }
        let ux = dx / length, uy = dy / length
        // Across the flank, pointing into the body of the mountain.
        let nx = -uy, ny = ux

        return (1..<count).map { i in
            let t = Double(i) / Double(count)
            let root = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            // Long at the top, short at the foot, with a swell through the
            // middle so the inner edge of the shading is not a straight line.
            let swell = sin(t * .pi)
            let reach = (20.0 * (1 - t) + 4.0) * (0.75 + 0.35 * swell)
            return Hachure(
                from: root,
                to: CGPoint(x: root.x + nx * reach, y: root.y + ny * reach),
                weight: 1.9 - 0.9 * t)
        }
    }
}
