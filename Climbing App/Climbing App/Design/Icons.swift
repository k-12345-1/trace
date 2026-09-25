import SwiftUI

/// The icon set, traced from the Lineage Health app's own so the two feel like
/// they came out of the same drawer.
///
/// Both are stroked outlines in a 24 unit box at weight 1.6, with round caps and
/// joins. There is no filled variant: an active tab changes colour, it does not
/// change shape, which is what keeps the bar from flickering between two
/// different drawings as you move across it.
enum Ic {
    static let box: CGFloat = 24
    static let weight: CGFloat = 1.6

    /// M3 11l9-7 9 7v9a2 2 0 01-2 2h-4v-7H9v7H5a2 2 0 01-2-2v-9z
    ///
    /// The doorway is cut out of the outline rather than drawn as a second
    /// shape, which is why it is one continuous path.
    ///
    /// Its jambs sit at x 9 and 15, so it is centred on the ridge at 12. The
    /// first trace of this put the right jamb at 16, which centred the doorway
    /// on 12.5 and left the whole icon looking very slightly askew without
    /// anything obviously wrong with it.
    struct Home: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / Ic.box
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
            }
            var path = Path()
            path.move(to: p(3, 11))
            path.addLine(to: p(12, 4))
            path.addLine(to: p(21, 11))
            path.addArc(tangent1End: p(21, 22), tangent2End: p(15, 22), radius: 2 * s)
            path.addLine(to: p(15, 22))
            path.addLine(to: p(15, 15))
            path.addLine(to: p(9, 15))
            path.addLine(to: p(9, 22))
            path.addLine(to: p(5, 22))
            path.addArc(tangent1End: p(3, 22), tangent2End: p(3, 11), radius: 2 * s)
            path.addLine(to: p(3, 11))
            path.closeSubpath()
            return path
        }
    }

    /// A head and a pair of shoulders: circle(12,8,r4) and M4 21a8 8 0 0116 0.
    struct User: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / Ic.box
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
            }
            var path = Path()
            path.addEllipse(in: CGRect(x: p(8, 4).x, y: p(8, 4).y, width: 8 * s, height: 8 * s))
            path.move(to: p(4, 21))
            path.addArc(center: p(12, 21), radius: 8 * s,
                        startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            return path
        }
    }
}

/// A stroked icon at a given size and colour, drawn the way the reference draws
/// them rather than at whatever weight a system symbol happens to be.
struct StrokeIcon<S: Shape>: View {
    let shape: S
    var size: CGFloat = 22
    var color: Color = Theme.ink

    var body: some View {
        shape
            .stroke(color,
                    style: StrokeStyle(lineWidth: Ic.weight * (size / Ic.box),
                                       lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 24) {
        StrokeIcon(shape: Ic.Home(), size: 44, color: Theme.blue)
        StrokeIcon(shape: Ic.User(), size: 44, color: Theme.blue)
    }
    .padding(40)
}
