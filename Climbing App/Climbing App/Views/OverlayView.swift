import SwiftUI

/// Draws the climber on top of their own footage.
///
/// The body is a wireframe rather than a stick figure: every limb is a tapered
/// tube described by ribs and two edge lines, built from the same 2D joints as
/// before. No body model and no depth, just the joints drawn as volumes instead
/// of lines, which is what makes it read as a body rather than a diagram.
///
/// Alongside it runs a live readout naming what the climber is doing at this
/// instant, in the manner of PlayVision's player labels.
struct OverlayView: View {
    let frames: [PoseFrame]
    let comPath: [CGPoint]
    let time: Double
    /// width / height of the video as displayed.
    let videoAspect: Double
    var showReadout: Bool = true

    /// Phases are derived once, not per frame of playback.
    private var phases: [MovementPhase] { PhaseTimeline.build(frames: frames) }

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size)
            let readout = showReadout
                ? PhaseTimeline.readout(frames: frames, phases: phases, at: time) : nil

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawTrace(ctx: &ctx, rect: rect)
                    if let frame = nearestFrame() {
                        drawWireframe(ctx: &ctx, frame: frame, rect: rect)
                    }
                    if let box = readout?.box { drawBrackets(ctx: &ctx, box: box, rect: rect) }
                }
                .allowsHitTesting(false)

                if let readout {
                    panel(readout)
                        .position(panelPosition(for: readout.box, in: rect, size: geo.size))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Live readout

    private func panel(_ r: PhaseTimeline.Readout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.phase.label.uppercased())
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(r.phase.isNotable ? Theme.accentText : Theme.chalk)
            HStack(spacing: 8) {
                readoutValue(String(format: "%.1f", r.speed), "bl/s")
                if let elbow = r.elbow {
                    readoutValue("\(Int(elbow.rounded()))", "deg")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.72))
        .overlay(Rectangle().stroke(Theme.chalk.opacity(0.28), lineWidth: 1))
        .fixedSize()
    }

    private func readoutValue(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(Theme.mono(11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.chalk)
            Text(unit)
                .font(Theme.mono(8))
                .foregroundStyle(Theme.chalk.opacity(0.55))
        }
    }

    /// Sits beside the climber's box, and flips to the other side rather than
    /// running off the frame.
    private func panelPosition(for box: CGRect, in rect: CGRect, size: CGSize) -> CGPoint {
        let boxRight = rect.minX + box.maxX * rect.width
        let boxLeft = rect.minX + box.minX * rect.width
        let y = rect.minY + box.minY * rect.height + 20
        let wantsRight = boxRight + 96 < size.width
        return CGPoint(x: wantsRight ? boxRight + 52 : max(58, boxLeft - 52),
                       y: min(max(y, 26), size.height - 26))
    }

    // MARK: Geometry

    private func fittedRect(in size: CGSize) -> CGRect {
        guard videoAspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let viewAspect = size.width / size.height
        if viewAspect > videoAspect {
            let w = size.height * videoAspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
        let h = size.width / videoAspect
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }

    private func map(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    private func nearestFrame() -> PoseFrame? {
        guard !frames.isEmpty else { return nil }
        return frames.min { abs($0.time - time) < abs($1.time - time) }
    }

    // MARK: Centre-of-mass trace

    private func drawTrace(ctx: inout GraphicsContext, rect: CGRect) {
        guard comPath.count > 1 else { return }
        var full = Path()
        full.addLines(comPath.map { map($0, rect) })
        ctx.stroke(full, with: .color(Theme.accent.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        let travelled = frames.filter { $0.com != nil && $0.time <= time }.compactMap { $0.com }
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

    // MARK: Tracked subject

    private func drawBrackets(ctx: inout GraphicsContext, box: CGRect, rect: CGRect) {
        let r = CGRect(x: rect.minX + box.minX * rect.width,
                       y: rect.minY + box.minY * rect.height,
                       width: box.width * rect.width,
                       height: box.height * rect.height)
        let arm = min(r.width, r.height) * 0.16
        var path = Path()
        for corner in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0),
                       (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            let (x, y, dx, dy) = corner
            path.move(to: CGPoint(x: x + arm * dx, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + arm * dy))
        }
        ctx.stroke(path, with: .color(Theme.chalk.opacity(0.55)), lineWidth: 1.5)
    }

    // MARK: The wireframe body

    /// Half-widths at each end of a limb, as a fraction of body height. A limb is
    /// a tapered tube, so the numbers differ at the two ends.
    private static let limbs: [(JointID, JointID, Double, Double)] = [
        (.leftShoulder, .leftElbow, 0.034, 0.026),
        (.leftElbow, .leftWrist, 0.026, 0.016),
        (.rightShoulder, .rightElbow, 0.034, 0.026),
        (.rightElbow, .rightWrist, 0.026, 0.016),
        (.leftHip, .leftKnee, 0.044, 0.032),
        (.leftKnee, .leftAnkle, 0.032, 0.019),
        (.rightHip, .rightKnee, 0.044, 0.032),
        (.rightKnee, .rightAnkle, 0.032, 0.019)
    ]

    private func drawWireframe(ctx: inout GraphicsContext, frame: PoseFrame, rect: CGRect) {
        let scale = (PhaseTimeline.boundingBox(frame)?.height ?? 0.5) * rect.height
        var mesh = Path()

        for (a, b, wa, wb) in Self.limbs {
            guard let p1 = frame.pt(a), let p2 = frame.pt(b) else { continue }
            addTube(&mesh, from: map(p1, rect), to: map(p2, rect),
                    startWidth: wa * scale, endWidth: wb * scale)
        }
        if let ls = frame.pt(.leftShoulder), let rs = frame.pt(.rightShoulder),
           let lh = frame.pt(.leftHip), let rh = frame.pt(.rightHip) {
            addTorso(&mesh, ls: map(ls, rect), rs: map(rs, rect),
                     lh: map(lh, rect), rh: map(rh, rect))
        }
        if let nose = frame.pt(.nose) {
            addHead(&mesh, at: map(nose, rect), radius: scale * 0.062)
        }

        // Dark first, so the fine lines survive a yellow hold underneath.
        ctx.stroke(mesh, with: .color(Color.black.opacity(0.62)), lineWidth: 2.6)
        ctx.stroke(mesh, with: .color(Theme.chalk.opacity(0.92)), lineWidth: 1)
    }

    /// A limb: ribs across it plus the two edges that join their ends.
    private func addTube(_ path: inout Path, from a: CGPoint, to b: CGPoint,
                         startWidth: Double, endWidth: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return }
        let ux = dx / length, uy = dy / length
        let px = -uy, py = ux

        let ribs = max(4, min(14, Int(length / 9)))
        var left: [CGPoint] = [], right: [CGPoint] = []

        for i in 0...ribs {
            let t = Double(i) / Double(ribs)
            let w = startWidth + (endWidth - startWidth) * t
            let cx = a.x + dx * t, cy = a.y + dy * t
            let l = CGPoint(x: cx + px * w, y: cy + py * w)
            let r = CGPoint(x: cx - px * w, y: cy - py * w)
            left.append(l); right.append(r)
            path.move(to: l); path.addLine(to: r)
        }
        path.addLines(left)
        path.addLines(right)
    }

    /// The torso as a quad with a grid across it.
    private func addTorso(_ path: inout Path, ls: CGPoint, rs: CGPoint,
                          lh: CGPoint, rh: CGPoint) {
        let rows = 7, cols = 4
        for i in 0...rows {
            let t = Double(i) / Double(rows)
            let l = lerp(ls, lh, t), r = lerp(rs, rh, t)
            path.move(to: l); path.addLine(to: r)
        }
        for j in 0...cols {
            let t = Double(j) / Double(cols)
            let top = lerp(ls, rs, t), bottom = lerp(lh, rh, t)
            path.move(to: top); path.addLine(to: bottom)
        }
    }

    /// The head as a few latitudes and longitudes, the way the reference draws a
    /// rounded form.
    private func addHead(_ path: inout Path, at c: CGPoint, radius: Double) {
        guard radius > 2 else { return }
        path.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius,
                                   width: radius * 2, height: radius * 2))
        for k in [-0.55, 0.0, 0.55] {
            let ry = radius * (1 - abs(k) * 0.82)
            let cy = c.y + radius * k
            path.addEllipse(in: CGRect(x: c.x - radius, y: cy - ry * 0.34,
                                       width: radius * 2, height: ry * 0.68))
        }
        path.move(to: CGPoint(x: c.x, y: c.y - radius))
        path.addLine(to: CGPoint(x: c.x, y: c.y + radius))
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
