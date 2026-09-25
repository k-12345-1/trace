import SwiftUI
import UIKit

/// The moment a finding is about, with the thing it is about drawn on it.
///
/// A still of somebody on a wall does not say what is wrong with it. Two things
/// are done about that here.
///
/// It crops in on the climber, so they are the picture rather than a figure in
/// the corner of a photograph of a wall. The crop is computed from the tracked
/// joints, so it follows them up the route.
///
/// And it draws the one measurement the finding rests on, with the corrected
/// version ghosted behind it: the bent elbow against a straight arm, the hips
/// against the line above the feet, the path taken against the line it could
/// have been. One comparison, not a diagram.
///
/// Only what the tracking can actually support is drawn. Three of the eight
/// leaks are geometric in a way a single frame can show; the rest get the
/// cropped picture and the words. A drawing of something the tracking cannot
/// see would be decoration that looks like evidence, which is worse than no
/// drawing at all.
struct FindingStill: View {
    let image: UIImage
    let finding: Finding
    let climb: Climb?
    /// Taller than a banner. A picture of a body part in a letterbox is mostly
    /// wall: the card's shape is what decides how much of a climber can be in
    /// it at once, and at a hundred and eighty points a pair of hips and the
    /// feet under them did not both fit.
    var height: CGFloat = 212

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let box = region(for: size)
            let scale = CGSize(width: size.width / max(box.width, 0.0001),
                               height: size.height / max(box.height, 0.0001))
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: scale.width, height: scale.height)
                    .offset(x: -box.minX * scale.width, y: -box.minY * scale.height)

                Canvas { ctx, _ in
                    draw(&ctx) { p in
                        CGPoint(x: (p.x - box.minX) * scale.width,
                                y: (p.y - box.minY) * scale.height)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Theme.surface2)
        .contentShape(Rectangle())
        .accessibilityLabel(finding.kind.title)
    }

    // MARK: What to look at

    /// The frame nearest the middle of the finding, which is the one the still
    /// was pulled from.
    private var pose: PoseFrame? {
        guard let frames = climb?.frames, !frames.isEmpty else { return nil }
        let at = finding.lookAt
        return frames
            .filter { !$0.joints.isEmpty }
            .min { abs($0.time - at) < abs($1.time - at) }
    }

    // MARK: The crop
    //
    // Worked out rather than left to scaledToFill, because a mark drawn on a
    // photograph has to land on the thing it is marking, and scaledToFill does
    // not say where it put the picture.

    private func region(for size: CGSize) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let subject = subject() else { return shaped(whole, to: size) }
        let margin = max(subject.width, subject.height) * 0.32
        return shaped(subject.insetBy(dx: -margin, dy: -margin), to: size)
    }

    /// What the card is a picture of, which is not the same as who is in it.
    ///
    /// Framing a finding about an elbow on the whole climber puts the elbow in
    /// the corner of a wide card, or past its edge: a body is tall and a card
    /// is wide, so the more of the body you keep the less of it you see. The
    /// subject is whatever the marks are drawn on, and nothing else.
    ///
    /// Nil means the whole photograph, which is right for the one finding that
    /// is about a route rather than a limb.
    private func subject() -> CGRect? {
        switch finding.kind {
        case .wandering:
            return nil
        case .bentArms:
            guard let arm = bentArm() else { return wholeBody() }
            return box([arm.shoulder, arm.elbow, arm.wrist])
        case .weightOnArms:
            guard let pose,
                  let hips = midpoint(pose, .leftHip, .rightHip),
                  let feet = midpoint(pose, .leftAnkle, .rightAnkle),
                  let shoulders = midpoint(pose, .leftShoulder, .rightShoulder)
            else { return wholeBody() }
            return box([hips, feet, shoulders, CGPoint(x: feet.x, y: shoulders.y)])
        default:
            return wholeBody()
        }
    }

    private func wholeBody() -> CGRect? {
        guard let pose else { return nil }
        return bounds(of: pose)
    }

    private func box(_ points: [CGPoint]) -> CGRect? {
        guard points.count >= 2 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(),
              let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return CGRect(x: x0, y: y0, width: max(x1 - x0, 0.001), height: max(y1 - y0, 0.001))
    }

    /// The box, grown to the card's shape and kept inside the picture.
    ///
    /// The shape has to match or the image is stretched: the view below draws
    /// the whole photograph at a size chosen so this box fills the card, which
    /// is only undistorted when the box has the card's own aspect measured in
    /// pixels.
    private func shaped(_ r: CGRect, to size: CGSize) -> CGRect {
        let pixels = image.size
        guard pixels.width > 0, pixels.height > 0,
              size.width > 0, size.height > 0, r.height > 0 else { return r }
        let wanted = (size.width / size.height) * (pixels.height / pixels.width)
        var w = r.width, h = r.height
        if w / h < wanted { w = h * wanted } else { h = w / wanted }
        if w > 1 { w = 1; h = w / wanted }
        if h > 1 { h = 1; w = h * wanted }
        let x = min(max(0, r.midX - w / 2), max(0, 1 - w))
        let y = min(max(0, r.midY - h / 2), max(0, 1 - h))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func bounds(of frame: PoseFrame) -> CGRect? {
        let points = Skeleton.dots.compactMap { frame.pt($0) }
        guard points.count >= 4 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(),
              let y0 = ys.min(), let y1 = ys.max(), y1 > y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: The marks

    private enum Ink {
        /// What happened. Read against a photograph of a gym, which is every
        /// color at once, so it is lightness that separates it rather than hue.
        static let now = Color(red: 1, green: 0.42, blue: 0.29)
        /// What it should have been.
        static let instead = Color.white
        static let casing = Color.black.opacity(0.55)
    }

    private func draw(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        switch finding.kind {
        case .bentArms:      drawBentArm(&ctx, at)
        case .weightOnArms:  drawHipsOverFeet(&ctx, at)
        case .wandering:     drawLine(&ctx, at)
        default:             break
        }
    }

    /// The more bent of the two arms, because that is the one costing something.
    private func bentArm() -> (shoulder: CGPoint, elbow: CGPoint,
                               wrist: CGPoint, angle: Double)? {
        guard let pose else { return nil }
        let arms: [(JointID, JointID, JointID)] = [
            (.leftShoulder, .leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow, .rightWrist)
        ]
        var worst: (shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint, angle: Double)?
        for (s, e, w) in arms {
            guard let sp = pose.pt(s), let ep = pose.pt(e), let wp = pose.pt(w),
                  let angle = angle(sp, ep, wp) else { continue }
            if worst == nil || angle < worst!.angle {
                worst = (sp, ep, wp, angle)
            }
        }
        return worst
    }

    /// The bent arm, against the straight one it could have been.
    private func drawBentArm(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        guard let arm = bentArm() else { return }

        // Where the arm would be straight: the same reach, along the line from
        // the shoulder to the hand. Not an invention, just the two ends joined.
        stroke(&ctx, [at(arm.shoulder), at(arm.wrist)],
               color: Ink.instead, width: 3, dash: [7, 6])
        stroke(&ctx, [at(arm.shoulder), at(arm.elbow), at(arm.wrist)],
               color: Ink.now, width: 3.5)
        dot(&ctx, at(arm.elbow), color: Ink.now)

        label(&ctx, "\(Int(arm.angle.rounded()))°", at: at(arm.elbow),
              offset: CGSize(width: 26, height: -16), color: Ink.now)
        label(&ctx, "180°", at: mid(at(arm.shoulder), at(arm.wrist)),
              offset: CGSize(width: -26, height: 16), color: Ink.instead)
    }

    /// The hips, against the line above the feet where they belong.
    private func drawHipsOverFeet(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        guard let pose,
              let hips = midpoint(pose, .leftHip, .rightHip),
              let feet = midpoint(pose, .leftAnkle, .rightAnkle),
              let shoulders = midpoint(pose, .leftShoulder, .rightShoulder)
        else { return }

        // Straight up from the feet, as far as the shoulders, which is the line
        // the hips would sit on with the weight through the legs.
        let top = CGPoint(x: feet.x, y: shoulders.y)
        stroke(&ctx, [at(feet), at(top)], color: Ink.instead, width: 3, dash: [7, 6])

        // And how far off it they are.
        let onLine = CGPoint(x: feet.x, y: hips.y)
        stroke(&ctx, [at(onLine), at(hips)], color: Ink.now, width: 3.5)
        dot(&ctx, at(hips), color: Ink.now)

        label(&ctx, "hips", at: at(hips),
              offset: CGSize(width: hips.x < feet.x ? -26 : 26, height: -16),
              color: Ink.now)
        label(&ctx, "over your feet", at: at(top),
              offset: CGSize(width: 0, height: -16), color: Ink.instead)
    }

    /// The line actually travelled, against the straight one.
    private func drawLine(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        guard let path = climb?.metrics.comPath, path.count >= 3,
              let first = path.first, let last = path.last else { return }
        stroke(&ctx, [at(first), at(last)], color: Ink.instead, width: 3, dash: [7, 6])
        stroke(&ctx, path.map(at), color: Ink.now, width: 3)
        label(&ctx, "the line you took", at: at(path[path.count / 2]),
              offset: CGSize(width: 0, height: -16), color: Ink.now)
    }

    // MARK: Drawing

    /// Every mark is laid on a dark casing first. A gym wall is painted every
    /// color there is, so a thin light line on its own disappears against
    /// whichever volume it crosses.
    private func stroke(_ ctx: inout GraphicsContext, _ points: [CGPoint],
                        color: Color, width: CGFloat, dash: [CGFloat] = []) {
        guard points.count >= 2 else { return }
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        ctx.stroke(path, with: .color(Ink.casing),
                   style: StrokeStyle(lineWidth: width + 3, lineCap: .round,
                                      lineJoin: .round, dash: dash))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round,
                                      lineJoin: .round, dash: dash))
    }

    private func dot(_ ctx: inout GraphicsContext, _ p: CGPoint, color: Color) {
        let r: CGFloat = 5
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5,
                                        width: (r + 1.5) * 2, height: (r + 1.5) * 2)),
                 with: .color(Ink.casing))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }

    private func label(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint,
                       offset: CGSize, color: Color) {
        let point = CGPoint(x: p.x + offset.width, y: p.y + offset.height)
        let resolved = ctx.resolve(
            Text(text).font(Theme.mono(10.5, weight: .medium)).foregroundStyle(color))
        let size = resolved.measure(in: CGSize(width: 200, height: 40))
        let pill = CGRect(x: point.x - size.width / 2 - 6, y: point.y - size.height / 2 - 3,
                          width: size.width + 12, height: size.height + 6)
        ctx.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2),
                 with: .color(Ink.casing))
        ctx.draw(resolved, at: point, anchor: .center)
    }

    // MARK: Geometry

    private func midpoint(_ f: PoseFrame, _ a: JointID, _ b: JointID) -> CGPoint? {
        guard let p = f.pt(a), let q = f.pt(b) else { return f.pt(a) ?? f.pt(b) }
        return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
    }

    private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// The angle at `b`, in degrees.
    private func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double? {
        let u = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let v = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let lu = (u.x * u.x + u.y * u.y).squareRoot()
        let lv = (v.x * v.x + v.y * v.y).squareRoot()
        guard lu > 1e-6, lv > 1e-6 else { return nil }
        let cosine = min(max((u.x * v.x + u.y * v.y) / (lu * lv), -1), 1)
        return acos(cosine) * 180 / .pi
    }
}
