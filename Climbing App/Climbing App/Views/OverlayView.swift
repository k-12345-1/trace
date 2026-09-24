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
    /// Metres per normalised image unit, when the climber has given their height.
    /// Without it every distance stays in body lengths, which is honest rather
    /// than inconvenient: the phone genuinely does not know.
    var metresPerUnit: Double? = nil
    /// Half the climber's span, in normalised units, when they have given it.
    var reachRadius: Double? = nil
    /// What the panel calls this climber. The route's own name, normally.
    var title: String = "Climber"

    /// The overlay palette: the app's four colours, on footage.
    ///
    /// A wall is painted every hue at once, so hue cannot be what separates the
    /// drawing from the wall behind it. Lightness does that instead. Every light
    /// mark is laid over a dark blue casing first, which is what makes white
    /// read on a white volume and light blue read on a blue jug. The casing is
    /// the whole reason a four colour overlay survives a gym.
    private enum Ink {
        static let bone = Color.white
        static let joint = Theme.blueLight
        static let trail = Theme.blueLight
        static let casing = Theme.blue
        static let chip = Theme.blue
        static let leader = Color.white.opacity(0.7)
        static let envelope = Color.white.opacity(0.9)
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
                }
                .allowsHitTesting(false)

                if let readout {
                    // A chip, not the panel. On a portrait clip the panel covers
                    // the climber it is describing, so the full telemetry lives
                    // under the stage and only the headline stays on the footage.
                    HStack(spacing: 8) {
                        Circle()
                            .fill(readout.phase.isNotable ? Ink.joint : .white.opacity(0.8))
                            .frame(width: 5, height: 5)
                        Text(readout.phase.label.uppercased())
                            .font(Theme.mono(9.5, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Ink.chip.opacity(0.9), in: Capsule())
                    .padding(.leading, rect.minX + 10)
                    .padding(.bottom, geo.size.height - rect.maxY + 10)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Telemetry

    /// The centre of mass one beat earlier, so the panel can show where it came
    /// from as well as where it is. Half a second back rather than one frame:
    /// a single frame's difference is inside the tracker's own noise.
    private func previousCOM(before t: Double) -> CGPoint? {
        frames.last { $0.time <= t - 0.5 && $0.com != nil }?.com
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
        let r = (reachRadius.map { $0 * rect.height }) ?? (scale * 0.58)
        guard r > 8 else { return }
        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.stroke(circle, with: .color(Ink.casing.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 3.6, lineCap: .butt, dash: [7, 7]))
        ctx.stroke(circle, with: .color(Ink.envelope),
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
            ctx.stroke(seg, with: .color(Ink.casing.opacity(alpha * 0.75)),
                       style: StrokeStyle(lineWidth: width + 2.2, lineCap: .round))
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
        // The casing first. Without it a white limb disappears against a white
        // volume, which is the one hold colour a gym always has.
        ctx.stroke(bones, with: .color(Ink.casing.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
        ctx.stroke(bones, with: .color(Ink.bone),
                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

        let r = max(2.6, scale * 0.017)
        for id in Skeleton.dots {
            guard let p = frame.pt(id) else { continue }
            let c = map(p, rect)
            ctx.fill(disc(at: c, r: r + 1.6), with: .color(Ink.casing))
            ctx.fill(disc(at: c, r: r), with: .color(Ink.joint))
        }
    }

    private func disc(at c: CGPoint, r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // MARK: Angle chips

    /// The joints worth a number: vertex, and the two joints that define the angle.
    /// The eight joints that get a number, each read as the angle at the middle
    /// joint between the two named either side of it.
    ///
    /// Every one is in degrees, and 180 means the limb is straight. An elbow at
    /// 180 is hanging off the skeleton; an elbow at 90 is being held there by
    /// the biceps, which is the single most expensive thing a climber does. The
    /// chip carries the degree sign for exactly that reason: a bare "136" reads
    /// as an identifier or a score, and it is neither.
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
            ctx.stroke(leader, with: .color(Ink.casing.opacity(0.7)), lineWidth: 2.6)
            ctx.stroke(leader, with: .color(Ink.leader), lineWidth: 1)

            chip(&ctx, text: "\(degrees)°", at: anchor, fontSize: size)
        }
    }

    private func chip(_ ctx: inout GraphicsContext, text: String, at c: CGPoint, fontSize: Double) {
        let resolved = ctx.resolve(
            Text(text).font(Theme.mono(fontSize, weight: .medium)).foregroundStyle(Color.white))
        let s = resolved.measure(in: CGSize(width: 200, height: 60))
        let box = CGRect(x: c.x - s.width / 2 - 6, y: c.y - s.height / 2 - 3.5,
                         width: s.width + 12, height: s.height + 7)
        ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2),
                 with: .color(Ink.chip.opacity(0.94)))
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

        ctx.fill(disc(at: c, r: r + 3), with: .color(Ink.casing))
        ctx.fill(disc(at: c, r: r + 1.6), with: .color(.white))
        ctx.fill(disc(at: c, r: r), with: .color(Theme.blue))

        var cross = Path()
        let arm = r * 0.62
        cross.move(to: CGPoint(x: c.x - arm, y: c.y)); cross.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - arm)); cross.addLine(to: CGPoint(x: c.x, y: c.y + arm))
        ctx.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // The label sits on its own plate rather than on the wall, because white
        // type on unknown footage is a coin toss.
        let size = max(9, min(13, rect.width * 0.030))
        let label = ctx.resolve(
            Text("COM").font(Theme.mono(size, weight: .bold)).foregroundStyle(.white))
        let s = label.measure(in: CGSize(width: 120, height: 40))
        let plate = CGRect(x: c.x + r + 7, y: c.y - s.height / 2 - 2.5,
                           width: s.width + 11, height: s.height + 5)
        ctx.fill(Path(roundedRect: plate, cornerRadius: plate.height / 2),
                 with: .color(Ink.chip.opacity(0.94)))
        ctx.draw(label, at: CGPoint(x: plate.midX, y: plate.midY), anchor: .center)
    }

}


// MARK: - Telemetry panel

/// The running commentary, in the shape PlayVision uses on a basketball player:
/// who is being tracked, what they are doing right now, where they are and how
/// fast, with the last reading kept beside the current one so a still frame
/// still shows direction.
///
/// Every field is a number Trace already had. Nothing here is estimated for the
/// sake of filling a row, which is why there is no force reading: a single
/// camera cannot measure the load through a finger, and a plausible-looking
/// newton figure would be the most quietly dishonest thing on the screen. The
/// elbow angle takes that slot instead, because it is measured, and because it
/// is the thing Trace actually coaches.
struct TelemetryPanel: View {
    let readout: PhaseTimeline.Readout
    let com: CGPoint?
    let previous: CGPoint?
    let metresPerUnit: Double?
    let title: String

    private let ground = Theme.blue.opacity(0.88)
    private let well = Color.white.opacity(0.07)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            field(label: "Current action", value: readout.phase.label,
                  emphasis: true, tint: readout.phase.isNotable ? Theme.blueLight : .white)

            HStack(spacing: 8) {
                field(label: "Position", value: positionText)
                field(label: "Velocity", value: velocityText)
            }
            HStack(spacing: 8) {
                field(label: elbowLabel, value: elbowText)
                footer
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(Theme.mono(9.5, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
        }
    }

    private func field(label: String, value: String,
                       emphasis: Bool = false, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Theme.mono(8.5, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(Theme.mono(emphasis ? 13 : 11, weight: emphasis ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Previous beside current, the way the reference keeps both. On a paused
    /// frame this is the only thing that says which way the climber was going.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CAME FROM")
                .font(Theme.mono(8.5, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.5))
            Text(coords(previous))
                .font(Theme.mono(11)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: The numbers

    /// Image coordinates, scaled to a thousand so they read as whole numbers
    /// rather than as a row of decimals. They are positions in the frame, not
    /// positions on the wall: the phone has no idea where the wall is.
    private func coords(_ p: CGPoint?) -> String {
        guard let p else { return "---" }
        return "\(Int((p.x * 1000).rounded())), \(Int((p.y * 1000).rounded()))"
    }

    private var positionText: String { coords(com) }

    /// Metres per second once the climber has given a height, body lengths per
    /// second before that. Body lengths are not a fallback for a missing number,
    /// they are the honest unit: a single camera cannot know the distance.
    private var velocityText: String {
        if let m = BodyScale.metresPerSecond(readout.speedRaw, metresPerUnit: metresPerUnit) {
            return String(format: "%.1f m/s", m)
        }
        return String(format: "%.2f bl/s", readout.speed)
    }

    private var elbowLabel: String {
        readout.elbow == nil ? "Elbows" : "Elbow angle"
    }

    private var elbowText: String {
        guard let e = readout.elbow else { return "Not visible" }
        let straightness = e >= 155 ? "straight" : e >= 130 ? "soft" : "bent"
        return "\(Int(e.rounded()))°  \(straightness)"
    }
}
