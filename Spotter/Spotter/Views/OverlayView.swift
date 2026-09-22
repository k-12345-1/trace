import SwiftUI

/// Draws the skeleton and the centre-of-mass trace on top of the footage.
///
/// The one design problem nobody else in this category has: climbing holds come in
/// every saturated hue there is, so the overlay cannot rely on colour to stand out.
/// The skeleton is chalk over a dark halo, which reads over a yellow hold and a
/// black mat alike. The accent is spent only on the COM trace.
struct OverlayView: View {
    let frames: [PoseFrame]
    let comPath: [CGPoint]
    let time: Double
    /// width / height of the video as displayed.
    let videoAspect: Double

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size)
            Canvas { ctx, _ in
                drawTrace(ctx: &ctx, rect: rect)
                if let frame = nearestFrame() {
                    drawSkeleton(ctx: &ctx, frame: frame, rect: rect)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Geometry

    /// The video is aspect-fitted, so the overlay has to letterbox the same way or
    /// every joint lands in the wrong place.
    private func fittedRect(in size: CGSize) -> CGRect {
        guard videoAspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let viewAspect = size.width / size.height
        if viewAspect > videoAspect {
            let w = size.height * videoAspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {
            let h = size.width / videoAspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
    }

    private func map(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    private func nearestFrame() -> PoseFrame? {
        guard !frames.isEmpty else { return nil }
        return frames.min { abs($0.time - time) < abs($1.time - time) }
    }

    // MARK: Drawing

    private func drawTrace(ctx: inout GraphicsContext, rect: CGRect) {
        guard comPath.count > 1 else { return }

        // The whole path sits faint so you can see the shape of the climb at once.
        var full = Path()
        full.addLines(comPath.map { map($0, rect) })
        ctx.stroke(full, with: .color(Theme.accent.opacity(0.28)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // What has already happened is bright.
        let travelled = travelledPoints()
        if travelled.count > 1 {
            var path = Path()
            path.addLines(travelled.map { map($0, rect) })
            ctx.stroke(path, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if let head = travelled.last {
                let p = map(head, rect)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                         with: .color(Theme.ground))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                         with: .color(Theme.accent))
            }
        }
    }

    private func travelledPoints() -> [CGPoint] {
        let tracked = frames.filter { $0.com != nil }
        guard !tracked.isEmpty else { return [] }
        return tracked.filter { $0.time <= time }.compactMap { $0.com }
    }

    private func drawSkeleton(ctx: inout GraphicsContext, frame: PoseFrame, rect: CGRect) {
        var bones = Path()
        for (a, b) in Skeleton.bones {
            guard let p1 = frame.pt(a), let p2 = frame.pt(b) else { continue }
            bones.move(to: map(p1, rect))
            bones.addLine(to: map(p2, rect))
        }
        guard !bones.isEmpty else { return }

        // Dark halo first. This is what makes it legible over any hold colour.
        ctx.stroke(bones, with: .color(Color.black.opacity(0.75)),
                   style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(bones, with: .color(Theme.chalk),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

        // Head
        if let nose = frame.pt(.nose) {
            let c = map(nose, rect)
            let r: CGFloat = max(rect.width, rect.height) * 0.018
            let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: box), with: .color(Color.black.opacity(0.75)), lineWidth: 5.5)
            ctx.stroke(Path(ellipseIn: box), with: .color(Theme.chalk), lineWidth: 2.5)
        }

        // Joints
        for id in Skeleton.dots {
            guard let p = frame.pt(id) else { continue }
            let c = map(p, rect)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.4, y: c.y - 3.4, width: 6.8, height: 6.8)),
                     with: .color(Color.black.opacity(0.75)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(Theme.chalk))
        }
    }
}
