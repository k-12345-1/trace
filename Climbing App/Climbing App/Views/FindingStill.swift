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
/// And it marks what is wrong. Where there is a corrected version that can
/// honestly be drawn, it is ghosted in behind: the bent elbow against a straight
/// arm, the hips against the line above the feet, the path taken against the
/// line it could have been. Where there is not, because the measurement is in
/// time rather than in space, the thing is circled and named. A foot placed
/// twice has no better position to draw, only a better habit.
///
/// Two inks and no third. Blue is what happened, white is what it should have
/// been, and both sit on a dark casing because a gym wall is painted every hue
/// there is: lightness is what separates a mark from it, never color.
struct FindingStill: View {
    let image: UIImage
    let finding: Finding
    let climb: Climb?
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let box = shaped(region, to: size)
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
        // The card takes its shape from what is in it rather than being a fixed
        // band. A wandering line is tall and thin and a bent elbow is neither,
        // and cropping both to one letterbox is what cut the ends off the line.
        .aspectRatio(cardAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Theme.surface2)
        .contentShape(Rectangle())
        .accessibilityLabel(finding.kind.title)
    }

    // MARK: What to look at

    /// The frame the still was pulled from, so the marks land on the picture.
    private var pose: PoseFrame? {
        guard let climb, let at = Self.instant(for: finding, in: climb) else { return nil }
        return climb.frames.min { abs($0.time - at) < abs($1.time - at) }
    }

    /// When to take the still.
    ///
    /// The middle of the finding's window is where the thing described is most
    /// likely to be, and also, often, where nobody is. A finding that could not
    /// name a moment covers the whole climb, so its middle is 0.6 seconds in,
    /// and at 0.6 seconds the climber is frequently still walking up to the
    /// wall: the card then showed an empty wall with a line drawn across it.
    ///
    /// Worse, the picture and the marks were chosen separately. The image came
    /// from the middle of the window and the skeleton from the nearest frame
    /// that had any joints in it, which on a clip with a gap could be seconds
    /// away, so the marks described a moment the picture was not of.
    ///
    /// One instant now, picked as the best-tracked moment inside the window,
    /// and both the image and the marks come from it. Nil when the climber was
    /// never tracked well enough anywhere, in which case there is no still to
    /// show and the card does without one.
    static func instant(for finding: Finding, in climb: Climb?) -> Double? {
        guard let frames = climb?.frames else { return nil }
        let tracked = frames.filter { $0.com != nil && $0.joints.count >= Self.enoughJoints }
        guard !tracked.isEmpty else { return nil }

        let inside = tracked.filter { $0.time >= finding.start && $0.time <= finding.end }
        let pool = inside.isEmpty ? tracked : inside
        let target = finding.lookAt
        return pool.min { abs($0.time - target) < abs($1.time - target) }?.time
    }

    /// Enough of a skeleton to be a climber rather than an arm in the corner.
    static let enoughJoints = 8

    // MARK: The crop
    //
    // Worked out rather than left to scaledToFill, because a mark drawn on a
    // photograph has to land on the thing it is marking, and scaledToFill does
    // not say where it put the picture.

    /// What is shown, in the photograph's own coordinates.
    ///
    /// Worked out before the card is sized rather than after, which is the
    /// whole trick: the card then takes its shape from this, so nothing has to
    /// be cropped away to make a subject fit a letterbox it was never going to
    /// fit.
    /// How much of the photograph the card keeps, whatever the subject's size.
    ///
    /// Two floors, and they exist because the first version had neither. The
    /// crop follows the marks, and the marks for a finding about two feet are a
    /// hand's width apart, so the card was a fifty pixel box blown up to three
    /// hundred and fifty points: a brown smear with two rings on it, and no way
    /// to tell it was a picture of a foot at all.
    ///
    /// The first floor keeps a share of the frame, so there is enough around
    /// the subject to recognise what you are looking at. The second keeps
    /// enough source pixels that the card is a photograph rather than an
    /// interpolation of one.
    static let minimumShare = 0.34
    static let minimumPixels = 460.0

    private var region: CGRect { Self.crop(subject: subject(), pixels: image.size) }

    /// The crop, as arithmetic, so it can be argued with in a test.
    static func crop(subject: CGRect?, pixels: CGSize) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let subject else { return whole }
        let margin = max(subject.width, subject.height) * 0.32
        let grown = subject.insetBy(dx: -margin, dy: -margin)

        let floorX = pixels.width > 0
            ? max(minimumShare, minimumPixels / pixels.width) : minimumShare
        let floorY = pixels.height > 0
            ? max(minimumShare, minimumPixels / pixels.height) : minimumShare

        let w = min(max(grown.width, floorX), 1)
        let h = min(max(grown.height, floorY), 1)
        return CGRect(x: min(max(0, grown.midX - w / 2), 1 - w),
                      y: min(max(0, grown.midY - h / 2), 1 - h),
                      width: w, height: h)
    }

    /// The card's shape, from the region's own, in points rather than in
    /// normalized units. Clamped at both ends: a card is a card, not a poster.
    private var cardAspect: CGFloat {
        let pixels = image.size
        let r = region
        guard pixels.width > 0, pixels.height > 0, r.width > 0, r.height > 0
        else { return 1.6 }
        let a = (r.width * pixels.width) / (r.height * pixels.height)
        return min(max(a, 0.72), 2.0)
    }

    /// What the card is a picture of, which is not the same as who is in it.
    ///
    /// Framing a finding about an elbow on the whole climber puts the elbow in
    /// the corner of a wide card, or past its edge: a body is tall and a card
    /// is wide, so the more of the body you keep the less of it you see. The
    /// subject is whatever the marks are drawn on, and nothing else.
    ///
    /// Nil means the whole photograph.
    private func subject() -> CGRect? {
        switch finding.kind {
        case .wandering:
            // The line, over the seconds this card is about.
            //
            // It used to be the whole climb: thirty seconds of path drawn on
            // one frame, under a heading that said "0:02 · 1.2s". The dashed
            // hold-to-hold line then ran corner to corner because it belonged
            // to a move somewhere else entirely, and none of it described what
            // the card claimed to be describing.
            let path = windowPath()
            guard path.count >= 3 else { return nil }
            return box(path)
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
        case .impreciseFeet:
            guard let pose else { return nil }
            let feet = [JointID.leftAnkle, .rightAnkle].compactMap { pose.pt($0) }
            return feet.count == 2 ? box(feet) : wholeBody()
        case .hesitation:
            guard let pose else { return nil }
            let hands = [JointID.leftWrist, .rightWrist].compactMap { pose.pt($0) }
            return hands.count == 2 ? box(hands) : wholeBody()
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
        /// What happened.
        ///
        /// The app's own overlay blue, not a warning color. A gym wall is
        /// painted every hue there is, so hue is not what separates a mark from
        /// it: lightness is, and every mark here is laid on a dark casing
        /// first. Two inks, the blue and the white, and the difference between
        /// them is the whole message.
        static let now = Theme.blueLight
        /// What it should have been.
        static let instead = Color.white
        static let casing = Theme.blue.opacity(0.9)
    }

    private func draw(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        switch finding.kind {
        case .bentArms:      drawBentArm(&ctx, at)
        case .weightOnArms:  drawHipsOverFeet(&ctx, at)
        case .wandering:     drawLine(&ctx, at)
        case .impreciseFeet: circleJoints([.leftAnkle, .rightAnkle], "these", &ctx, at)
        case .hesitation:    circleJoints([.leftWrist, .rightWrist], "holding here", &ctx, at)
        case .unopposed:     drawUnopposed(&ctx, at)
        case .lurchy, .mistimedDynamics:
            circlePoint(pose?.com, "your weight", &ctx, at)
        }
    }

    /// A ring around the thing being talked about.
    ///
    /// For the findings with no geometry to compare against, which is most of
    /// them. There is no corrected version to ghost in for a foot that was
    /// placed twice or a hand that hung there too long: the measurement is in
    /// time, not in space. Pointing at where it happened is the honest amount
    /// of drawing, and it is more than the picture said before.
    private func circleJoints(_ ids: [JointID], _ caption: String,
                              _ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        guard let pose else { return }
        let points = ids.compactMap { pose.pt($0) }
        guard !points.isEmpty else { return }
        for p in points { ring(&ctx, at(p), radius: 26, color: Ink.now) }
        if let first = points.min(by: { $0.y < $1.y }) {
            label(&ctx, caption, at: at(first),
                  offset: CGSize(width: 0, height: -40), color: Ink.now)
        }
    }

    private func circlePoint(_ p: CGPoint?, _ caption: String,
                             _ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        guard let p else { return }
        ring(&ctx, at(p), radius: 30, color: Ink.now)
        label(&ctx, caption, at: at(p),
              offset: CGSize(width: 0, height: -44), color: Ink.now)
    }

    /// Where the weight was, and the span of contacts it should have been
    /// inside. The gap between them is the finding.
    private func drawUnopposed(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        guard let pose, let com = pose.com else { return }
        let contacts = [JointID.leftWrist, .rightWrist, .leftAnkle, .rightAnkle]
            .compactMap { pose.pt($0) }
        ring(&ctx, at(com), radius: 30, color: Ink.now)
        label(&ctx, "your weight", at: at(com),
              offset: CGSize(width: 0, height: -44), color: Ink.now)

        // The span your hands and feet actually covered, drawn at the height of
        // the nearest one so it reads as a floor rather than a horizon.
        if let left = contacts.map(\.x).min(), let right = contacts.map(\.x).max(),
           let y = contacts.map(\.y).min(), right > left {
            stroke(&ctx, [at(CGPoint(x: left, y: y)), at(CGPoint(x: right, y: y))],
                   color: Ink.instead, width: 3, dash: [7, 6])
            label(&ctx, "inside here", at: at(CGPoint(x: (left + right) / 2, y: y)),
                  offset: CGSize(width: 0, height: 18), color: Ink.instead)
        }
    }

    private func ring(_ ctx: inout GraphicsContext, _ p: CGPoint,
                      radius: CGFloat, color: Color) {
        let rect = CGRect(x: p.x - radius, y: p.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.stroke(Path(ellipseIn: rect), with: .color(Ink.casing),
                   style: StrokeStyle(lineWidth: 6))
        ctx.stroke(Path(ellipseIn: rect), with: .color(color),
                   style: StrokeStyle(lineWidth: 3))
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

    /// The line actually travelled, against the shortest way between each
    /// position and the next.
    ///
    /// Not against a straight line up the wall. That line does not exist on a
    /// boulder, and drawing it told a climber who followed a diagonal problem
    /// perfectly that they had gone badly wrong. Each white segment here runs
    /// between two places they actually were, so it is a line they could have
    /// taken, and the blue is what they took instead.
    private func drawLine(_ ctx: inout GraphicsContext, _ at: (CGPoint) -> CGPoint) {
        let path = windowPath()
        guard path.count >= 3 else { return }

        // Only the moves that happened inside this window. A move from another
        // part of the climb drew a dashed line across the whole picture with
        // both of its ends somewhere off it.
        let moves = (climb.flatMap { MoveEngine.read(frames: $0.frames) }?.moves ?? [])
            .filter { $0.end > finding.start && $0.start < finding.end }

        for move in moves {
            stroke(&ctx, [at(move.from), at(move.to)],
                   color: Ink.instead, width: 2.5, dash: [6, 5])
        }
        stroke(&ctx, path.map(at), color: Ink.now, width: 3)
        if let worst = moves.max(by: { $0.waste < $1.waste }) {
            label(&ctx, "hold to hold", at: mid(at(worst.from), at(worst.to)),
                  offset: CGSize(width: 0, height: 18), color: Ink.instead)
        }

        label(&ctx, "the line you took", at: at(path[path.count / 2]),
              offset: CGSize(width: 0, height: -18), color: Ink.now)
    }

    /// The centre-of-mass path over the seconds this finding covers.
    ///
    /// Falls back to the whole path when the window holds too little to draw,
    /// because a card with no line on it says less than one with a long line.
    private func windowPath() -> [CGPoint] {
        guard let climb else { return [] }
        let inside = climb.frames
            .filter { $0.time >= finding.start && $0.time <= finding.end }
            .compactMap { $0.com }
        return inside.count >= 3 ? inside : climb.metrics.comPath
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
