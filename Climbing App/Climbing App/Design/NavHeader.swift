import SwiftUI

/// The back control from the Lineage Health app: a left arrow inside a dashed
/// ring.
///
/// The dash pattern is not decorative. Twenty even dashes divide the real
/// circumference of a 16.5 radius circle (2π·16.5 ≈ 103.67) exactly, so the
/// pattern closes with no mismatched seam, and a half-period offset centres a
/// whole dash at twelve o'clock rather than cutting one in half there.
struct BackRing: View {
    var color: Color = Theme.ink
    var size: CGFloat = 36
    /// Drawn over footage rather than paper: the ring gets a disc behind it.
    var onPhoto: Bool = false

    private static let radius: CGFloat = 16.5
    private static let dash: CGFloat = 2.0735
    private static let gap: CGFloat = 3.1102
    private static let phase: CGFloat = 2.59185

    var body: some View {
        let k = size / 36

        ZStack {
            if onPhoto {
                Circle().fill(.black.opacity(0.32))
            }

            Circle()
                .stroke(color.opacity(onPhoto ? 0.9 : 0.55),
                        style: StrokeStyle(lineWidth: 1 * k,
                                           dash: [Self.dash * k, Self.gap * k],
                                           dashPhase: Self.phase * k))
                .frame(width: Self.radius * 2 * k, height: Self.radius * 2 * k)
                .rotationEffect(.degrees(-90))

            Arrow()
                .stroke(color, style: StrokeStyle(lineWidth: 1.6 * k,
                                                  lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }

    /// The shaft and the chevron, placed the way the reference places them:
    /// scaled to three quarters and centred just right of the ring's middle.
    private struct Arrow: Shape {
        func path(in rect: CGRect) -> Path {
            let k = min(rect.width, rect.height) / 36
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + (19 + 0.75 * (x - 12)) * k,
                        y: rect.minY + (18 + 0.75 * (y - 12)) * k)
            }
            var path = Path()
            path.move(to: p(19, 12)); path.addLine(to: p(5, 12))
            path.move(to: p(11, 6)); path.addLine(to: p(5, 12)); path.addLine(to: p(11, 18))
            return path
        }
    }
}

/// A pushed screen's header: the ringed back control, and a title beside it.
///
/// The app hides the system navigation bar, so without this a pushed screen's
/// only way out is the edge swipe, which is a gesture rather than a control.
struct NavHeader: View {
    var title: String?
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                BackRing()
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            if let title {
                Text(title)
                    .font(Theme.serif(19, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter - 4)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

/// The same control, for a screen whose header is a photograph.
struct BackOverlayButton: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            BackRing(color: .white, size: 40, onPhoto: true)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        NavHeader(title: "Personal info") { }
        BackRing()
        BackRing(color: .white, size: 40, onPhoto: true).background(Theme.blue)
    }
    .padding()
}
