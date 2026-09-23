import SwiftUI

/// The Trace mark: a mountain drawn as a wireframe.
///
/// It is the same idea as the overlay. Trace looks at a climber and draws the
/// structure underneath them rather than the surface, so the mark is a mountain
/// with its structure showing rather than a filled silhouette.
///
/// The geometry is fixed, not sketched. Five points, a lattice at a stated angle
/// and a stated spacing, one pen weight throughout. It is the same construction
/// the app icon is rendered from, so the two cannot drift apart.
struct MountainMark: View {
    var color: Color = Theme.blue
    /// Fraction of the frame left empty around the mark.
    var inset: Double = 0.06

    /// The outline, in a 100 by 100 design space. Left shoulder lower and
    /// broader, main peak right and higher.
    static let outline: [CGPoint] = [
        CGPoint(x: 9, y: 78), CGPoint(x: 33, y: 41), CGPoint(x: 45, y: 53),
        CGPoint(x: 62, y: 20), CGPoint(x: 91, y: 78)
    ]

    static let latticeAngles: [Double] = [58, -58]
    static let latticeSpacing: Double = 17
    static let outlineWeight: Double = 4.0
    static let latticeWeight: Double = 3.2

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let scale = (side * (1 - inset * 2)) / 100
            let ox = (size.width - 100 * scale) / 2
            let oy = (size.height - 100 * scale) / 2
            func p(_ q: CGPoint) -> CGPoint {
                CGPoint(x: ox + q.x * scale, y: oy + q.y * scale)
            }

            var shape = Path()
            shape.addLines(Self.outline.map(p))
            shape.closeSubpath()

            // The lattice only exists inside the mountain.
            ctx.drawLayer { inner in
                inner.clip(to: shape)
                var mesh = Path()
                for angle in Self.latticeAngles {
                    addLattice(&mesh, angle: angle, scale: scale, ox: ox, oy: oy)
                }
                inner.stroke(mesh, with: .color(color),
                             style: StrokeStyle(lineWidth: Self.latticeWeight * scale,
                                                lineCap: .butt))
            }

            ctx.stroke(shape, with: .color(color),
                       style: StrokeStyle(lineWidth: Self.outlineWeight * scale,
                                          lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    /// Parallel lines at one angle, far enough past the edges to cross the whole
    /// mountain whatever the angle.
    private func addLattice(_ path: inout Path, angle: Double,
                            scale: Double, ox: Double, oy: Double) {
        let a = angle * .pi / 180
        let dx = cos(a), dy = sin(a)
        let nx = -dy, ny = dx
        let reach = 160.0
        let steps = Int(200 / Self.latticeSpacing)
        for i in -steps...steps {
            let offset = Double(i) * Self.latticeSpacing
            let cx = 50 + nx * offset, cy = 50 + ny * offset
            let from = CGPoint(x: ox + (cx - dx * reach) * scale,
                               y: oy + (cy - dy * reach) * scale)
            let to = CGPoint(x: ox + (cx + dx * reach) * scale,
                             y: oy + (cy + dy * reach) * scale)
            path.move(to: from)
            path.addLine(to: to)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MountainMark(color: .white)
            .frame(width: 180, height: 180)
            .background(Theme.blue)
        MountainMark()
            .frame(width: 56, height: 56)
    }
    .padding()
}
