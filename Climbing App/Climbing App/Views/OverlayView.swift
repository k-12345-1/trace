import SwiftUI

/// Draws the climber on top of their own footage, in the language of the
/// reference clip: a teal skeleton with yellow joints, magenta trails behind
/// every extremity, angle chips on leader lines, and a marked centre of mass
/// sitting inside its balance envelope.
///
/// Nothing new is measured. Every number here already exists in MetricsEngine;
/// this is the readout, not the analysis.
struct OverlayView: View {
    let frames: [PoseFrame]
    let time: Double
    /// width / height of the video as displayed.
    let videoAspect: Double
    var showReadout: Bool = true

    /// The overlay palette. Deliberately not Theme's: these colours have to sit
    /// on top of a gym wall painted every hue at once, so they are chosen for
    /// separation from holds rather than for brand agreement.
    private enum Ink {
        static let bone = Color(red: 0.09, green: 0.72, blue: 0.68)      // teal
        static let joint = Color(red: 1.00, green: 0.77, blue: 0.00)     // yellow
        static let trail = Color(red: 1.00, green: 0.24, blue: 0.59)     // magenta
        static let chip = Color(red: 0.11, green: 0.11, blue: 0.12)
        static let leader = Color.white.opacity(0.55)
        static let envelope = Color.white.opacity(0.85)
    }

    /// How far back the extremity trails reach.
    private static let trailSeconds = 1.5

    private var phases: [MovementPhase] { PhaseTimeline.build(frames: frames) }

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size)
            let frame = nearestFrame()
            let readout = showReadout
                ? PhaseTimeline.readout(frames: frames, phases: phases, at: time) : nil

            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, _ in
                    guard let frame else { return }
                    let scale = bodyHeight(frame) * rect.height

                    drawEnvelope(ctx: &ctx, frame: frame, rect: rect, scale: scale)
                    drawTrails(ctx: &ctx, rect: rect)
                    drawSkeleton(ctx: &ctx, frame: frame, rect: rect, scale: scale)
                    drawAngles(ctx: &ctx, frame: frame, rect: rect, scale: scale)
                    drawCOM(ctx: &ctx, frame: frame, rect: rect, scale: scale)
                    drawInset(ctx: &ctx, frame: frame, in: rect)
                }
                .allowsHitTesting(false)

                if let readout {
                    phaseChip(readout)
                        .padding(.leading, rect.minX + 12)
                        .padding(.bottom, geo.size.height - rect.maxY + 12)
                }
            }
        }
    }

    // MARK: Phase chip
    //
    // The reference has no text panel, so this borrows the chip language of the
    // angle labels and stays in one corner rather than chasing the climber.

    private func phaseChip(_ r: PhaseTimeline.Readout) -> some View {
        HStack(spacing: 9) {
            Text(r.phase.label.uppercased())
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(r.phase.isNotable ? Ink.joint : .white)
            Text(String(format: "%.1f bl/s", r.speed))
                .font(Theme.mono(10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Ink.chip.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
        .allowsHitTesting(false)
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

    /// Normalised body height, used as the scale for every drawn size so the
    /// overlay keeps its proportions whether the climber fills the frame or not.
    private func bodyHeight(_ frame: PoseFrame) -> Double {
        Double(PhaseTimeline.boundingBox(frame)?.height ?? 0.5)
    }

    // MARK: Balance envelope

    /// A circle on the centre of mass, the radius of the climber's own reach.
    /// It is not a measurement, it is a frame of reference: when a hold sits
    /// outside it, the move needs a shift before it needs more strength.
    private func drawEnvelope(ctx: inout GraphicsContext, frame: PoseFrame,
                              rect: CGRect, scale: Double) {
        guard let com = frame.com else { return }
        let c = map(com, rect)
        let r = scale * 0.58
        guard r > 8 else { return }
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(Ink.envelope),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .butt, dash: [7, 7]))
    }

    // MARK: Trails

    /// Where each hand, each foot and the centre of mass have just been. The
    /// trail is what makes a jerky pull look jerky: a clean move leaves a clean
    /// arc, a scrappy one leaves a scribble.
    private func drawTrails(ctx: inout GraphicsContext, rect: CGRect) {
        let window = frames.filter { $0.time <= time && $0.time >= time - Self.trailSeconds }
        guard window.count > 1 else { return }

        for joint in [JointID.leftWrist, .rightWrist, .leftAnkle, .rightAnkle] {
            stroke(trail: window.map { $0.pt(joint) }, times: window.map { $0.time },
                   ctx: &ctx, rect: rect, width: 2.2, peak: 0.95)
        }
        stroke(trail: window.map { $0.com }, times: window.map { $0.time },
               ctx: &ctx, rect: rect, width: 1.6, peak: 0.45)
    }

    /// One trail, faded from nothing at its tail to full at the climber.
    private func stroke(trail points: [CGPoint?], times: [Double], ctx: inout GraphicsContext,
                        rect: CGRect, width: Double, peak: Double) {
        guard points.count > 1 else { return }
        let span = max(Self.trailSeconds, 0.001)
        for i in 1..<points.count {
            guard let a = points[i - 1], let b = points[i] else { continue }
            let age = (time - times[i]) / span
            let alpha = peak * max(0, 1 - age * age)
            guard alpha > 0.03 else { continue }
            var seg = Path()
            seg.move(to: map(a, rect)); seg.addLine(to: map(b, rect))
            ctx.stroke(seg, with: .color(Ink.trail.opacity(alpha)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    // MARK: Skeleton

    private func drawSkeleton(ctx: inout GraphicsContext, frame: PoseFrame,
                              rect: CGRect, scale: Double) {
        var bones = Path()
        for (a, b) in Skeleton.bones {
            guard let p1 = frame.pt(a), let p2 = frame.pt(b) else { continue }
            bones.move(to: map(p1, rect)); bones.addLine(to: map(p2, rect))
        }
        // A dark pass first: holds are every saturated hue, and teal on yellow
        // disappears without something behind it.
        ctx.stroke(bones, with: .color(.black.opacity(0.42)),
                   style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round))
        ctx.stroke(bones, with: .color(Ink.bone),
                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

        let r = max(2.4, scale * 0.016)
        for id in Skeleton.dots {
            guard let p = frame.pt(id) else { continue }
            let c = map(p, rect)
            ctx.fill(disc(at: c, r: r + 1.1), with: .color(.black.opacity(0.45)))
            ctx.fill(disc(at: c, r: r), with: .color(Ink.joint))
        }
    }

    private func disc(at c: CGPoint, r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // MARK: Angle chips

    /// The joints worth a number: vertex, and the two joints that define the angle.
    private static let angled: [(JointID, JointID, JointID)] = [
        (.leftElbow, .leftShoulder, .leftWrist),
        (.rightElbow, .rightShoulder, .rightWrist),
        (.leftShoulder, .leftElbow, .leftHip),
        (.rightShoulder, .rightElbow, .rightHip),
        (.leftHip, .leftShoulder, .leftKnee),
        (.rightHip, .rightShoulder, .rightKnee),
        (.leftKnee, .leftHip, .leftAnkle),
        (.rightKnee, .rightHip, .rightAnkle)
    ]

    private func drawAngles(ctx: inout GraphicsContext, frame: PoseFrame,
                            rect: CGRect, scale: Double) {
        let size = min(13, max(8.5, rect.width * 0.030))
        let reach = max(42, scale * 0.30)
        let centre = frame.com.map { map($0, rect) }

        for (vertex, a, b) in Self.angled {
            guard let v = frame.pt(vertex), let pa = frame.pt(a), let pb = frame.pt(b)
            else { continue }
            let joint = map(v, rect)
            let degrees = Int(MetricsEngine.angle(at: v, from: pa, to: pb).rounded())

            // Chips splay outward from the body, so they land on wall rather
            // than on the climber and keep clear of one another.
            let away = unit(from: centre ?? joint, to: joint, fallback: CGPoint(x: 0, y: -1))
            let anchor = CGPoint(x: joint.x + away.x * reach, y: joint.y + away.y * reach)

            var leader = Path()
            leader.move(to: joint); leader.addLine(to: anchor)
            ctx.stroke(leader, with: .color(Ink.leader), lineWidth: 1)

            chip(&ctx, text: "\(degrees)", at: anchor, fontSize: size)
        }
    }

    private func chip(_ ctx: inout GraphicsContext, text: String, at c: CGPoint, fontSize: Double) {
        let resolved = ctx.resolve(
            Text(text).font(Theme.mono(fontSize, weight: .medium)).foregroundStyle(Color.white))
        let s = resolved.measure(in: CGSize(width: 200, height: 60))
        let box = CGRect(x: c.x - s.width / 2 - 6, y: c.y - s.height / 2 - 3.5,
                         width: s.width + 12, height: s.height + 7)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(Ink.chip.opacity(0.92)))
        ctx.draw(resolved, at: c, anchor: .center)
    }

    private func unit(from a: CGPoint, to b: CGPoint, fallback: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.5 else { return fallback }
        return CGPoint(x: dx / len, y: dy / len)
    }

    // MARK: Centre of mass

    private func drawCOM(ctx: inout GraphicsContext, frame: PoseFrame,
                         rect: CGRect, scale: Double) {
        guard let com = frame.com else { return }
        let c = map(com, rect)
        let r = max(7.0, scale * 0.032)

        ctx.fill(disc(at: c, r: r + 2), with: .color(.white))
        ctx.fill(disc(at: c, r: r), with: .color(Ink.trail))

        var cross = Path()
        let arm = r * 0.62
        cross.move(to: CGPoint(x: c.x - arm, y: c.y)); cross.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - arm)); cross.addLine(to: CGPoint(x: c.x, y: c.y + arm))
        ctx.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        let label = ctx.resolve(
            Text("COM")
                .font(Theme.mono(max(9, min(13, rect.width * 0.030)), weight: .bold))
                .foregroundStyle(Ink.trail))
        ctx.draw(label, at: CGPoint(x: c.x + r + 7, y: c.y), anchor: .leading)
    }

    // MARK: Isolated pose inset

    /// The skeleton on its own, away from the wall. Holds are visual noise when
    /// what you are looking at is the shape of the body.
    private func drawInset(ctx: inout GraphicsContext, frame: PoseFrame, in rect: CGRect) {
        let side = min(86, rect.width * 0.22)
        guard side > 40, let box = PhaseTimeline.boundingBox(frame) else { return }
        let panel = CGRect(x: rect.maxX - side - 10, y: rect.minY + rect.height * 0.38,
                           width: side, height: side)
        ctx.fill(Path(roundedRect: panel, cornerRadius: 9), with: .color(.black.opacity(0.46)))
        ctx.stroke(Path(roundedRect: panel, cornerRadius: 9),
                   with: .color(.white.opacity(0.14)), lineWidth: 1)

        let pad = side * 0.14
        let fit = min((side - pad * 2) / max(box.width, 0.01),
                      (side - pad * 2) / max(box.height, 0.01))
        let ox = panel.midX - (box.midX * fit)
        let oy = panel.midY - (box.midY * fit)
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * fit, y: oy + p.y * fit) }

        var bones = Path()
        for (a, b) in Skeleton.bones {
            guard let p1 = frame.pt(a), let p2 = frame.pt(b) else { continue }
            bones.move(to: place(p1)); bones.addLine(to: place(p2))
        }
        ctx.stroke(bones, with: .color(Ink.bone),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        for id in Skeleton.dots {
            guard let p = frame.pt(id) else { continue }
            ctx.fill(disc(at: place(p), r: 1.5), with: .color(Ink.joint))
        }
    }
}
