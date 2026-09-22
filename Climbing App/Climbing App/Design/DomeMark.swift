import SwiftUI

/// The Trace mark: meridians swept between two poles, so a volume appears from
/// nothing but lines. The same geometry the app icon is cut from.
struct DomeMark: View {
    var color: Color = Theme.chalk
    /// Inner meridians carry the same colour at half strength, which is what
    /// gives the form its depth without a second hue.
    var innerOpacity: Double = 0.5
    var lineWidth: CGFloat = 4.4

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let w = lineWidth / 100 * s
            ZStack {
                meridian(28, in: s).stroke(color.opacity(innerOpacity), lineWidth: w)
                axis(in: s).stroke(color.opacity(innerOpacity), lineWidth: w)
                meridian(72, in: s).stroke(color.opacity(innerOpacity), lineWidth: w)
                meridian(14, in: s).stroke(color, lineWidth: w)
                meridian(86, in: s).stroke(color, lineWidth: w)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func p(_ x: Double, _ y: Double, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x / 100 * s, y: y / 100 * s)
    }

    private func meridian(_ control: Double, in s: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(50, 90, s))
        path.addCurve(to: p(50, 10, s),
                      control1: p(control, control == 14 || control == 86 ? 70 : 72, s),
                      control2: p(control, control == 14 || control == 86 ? 30 : 28, s))
        return path
    }

    private func axis(in s: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(50, 90, s))
        path.addLine(to: p(50, 10, s))
        return path
    }
}
