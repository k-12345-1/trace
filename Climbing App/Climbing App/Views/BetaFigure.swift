import SwiftUI

/// The figure on the photo.
///
/// Drawn the way the live skeleton is drawn on footage, white casing under
/// blue ink, so it reads as the same idea: a body Trace is describing. The
/// feet are ringed where they are on a hold and left open where they smear,
/// so the difference is visible without a legend.
struct BetaFigure: View {
    let pose: BetaEngine.Pose
    /// The rect the photo occupies inside the view.
    let rect: CGRect
    /// Arm span in photo units, for sizing the marks.
    let span: Double
    var shape: BetaEngine.Shape = .average

    private func at(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    var body: some View {
        Canvas { ctx, _ in
            // A body, not a wire, and not a set of blocks either: a trunk
            // with shoulders, a waist and hips, limbs that meet at round
            // joints, a neck, a head, hands and shoes. Every width is this
            // climber's own where their footage has been read. Drawn in
            // the live overlay's two inks so it reads as the same idea.
            let unit = rect.width * span
            let build = shape.shoulderWidth / 0.22
            let ink = Theme.blue.opacity(0.92)
            let casing = Theme.chalk.opacity(0.95)
            let edge = StrokeStyle(lineWidth: 2.5, lineJoin: .round)

            func capsule(_ a: CGPoint, _ b: CGPoint, from wa: Double, to wb: Double) -> Path {
                let p = at(a), q = at(b)
                let dx = q.x - p.x, dy = q.y - p.y
                let len = max(hypot(dx, dy), 0.001)
                let nx = -dy / len, ny = dx / len
                let ra = max(2.5, unit * wa * build), rb = max(2, unit * wb * build)
                var path = Path()
                path.move(to: CGPoint(x: p.x + nx * ra, y: p.y + ny * ra))
                path.addLine(to: CGPoint(x: q.x + nx * rb, y: q.y + ny * rb))
                path.addArc(center: q, radius: rb, startAngle: .radians(atan2(ny, nx)),
                            endAngle: .radians(atan2(ny, nx) + .pi), clockwise: true)
                path.addLine(to: CGPoint(x: p.x - nx * ra, y: p.y - ny * ra))
                path.addArc(center: p, radius: ra, startAngle: .radians(atan2(-ny, -nx)),
                            endAngle: .radians(atan2(-ny, -nx) + .pi), clockwise: true)
                path.closeSubpath()
                return path
            }
            func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            func draw(_ path: Path) {
                ctx.stroke(path, with: .color(casing), style: StrokeStyle(lineWidth: 5.5, lineJoin: .round))
                ctx.fill(path, with: .color(ink))
            }
            // A limb is two bones and a joint, drawn as one shape so the
            // casing runs round the outside only.
            func limb(_ a: CGPoint, _ j: CGPoint, _ b: CGPoint, from wa: Double, mid wj: Double, to wb: Double) {
                var path = capsule(a, j, from: wa, to: wj)
                path.addPath(capsule(j, b, from: wj, to: wb))
                path.addPath(disc(at(j), max(2.5, unit * wj * build)))
                draw(path)
            }

            // Shoes: a short capsule running on from the shin past the foot.
            func shoe(_ knee: CGPoint, _ foot: CGPoint) {
                let k = at(knee), f = at(foot)
                let dx = f.x - k.x, dy = f.y - k.y
                let len = max(hypot(dx, dy), 0.001)
                let toe = CGPoint(x: f.x + dx / len * unit * 0.035, y: f.y + dy / len * unit * 0.035)
                var path = Path()
                let r = max(3, unit * 0.026 * build)
                path.addPath(capsule(foot, CGPoint(x: (toe.x - rect.minX) / rect.width, y: (toe.y - rect.minY) / rect.height),
                                     from: 0.026, to: 0.03))
                _ = r
                draw(path)
            }

            // Legs behind the trunk.
            limb(pose.hips, pose.leftKnee, pose.leftFoot, from: 0.06, mid: 0.045, to: 0.03)
            limb(pose.hips, pose.rightKnee, pose.rightFoot, from: 0.06, mid: 0.045, to: 0.03)
            shoe(pose.leftKnee, pose.leftFoot)
            shoe(pose.rightKnee, pose.rightFoot)

            // The trunk: shoulders, a waist two thirds down, hips.
            let ls = at(pose.leftShoulder), rs = at(pose.rightShoulder), hp = at(pose.hips)
            let shoulderR = max(4, unit * 0.045 * build)
            let hipHalf = max(5, unit * shape.hipWidth / 2)
            let waistHalf = hipHalf * 0.85
            let neckMid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let down = CGPoint(x: hp.x - neckMid.x, y: hp.y - neckMid.y)
            let waist = CGPoint(x: neckMid.x + down.x * 0.68, y: neckMid.y + down.y * 0.68)
            let across = CGPoint(x: rs.x - ls.x, y: rs.y - ls.y)
            let acrossLen = max(hypot(across.x, across.y), 0.001)
            let ax = across.x / acrossLen, ay = across.y / acrossLen
            var trunk = Path()
            trunk.move(to: CGPoint(x: ls.x - ax * shoulderR, y: ls.y - ay * shoulderR))
            trunk.addLine(to: CGPoint(x: rs.x + ax * shoulderR, y: rs.y + ay * shoulderR))
            trunk.addCurve(to: CGPoint(x: hp.x + ax * hipHalf, y: hp.y + ay * hipHalf),
                           control1: CGPoint(x: rs.x + ax * shoulderR * 0.9 + down.x * 0.3, y: rs.y + ay * shoulderR * 0.9 + down.y * 0.3),
                           control2: CGPoint(x: waist.x + ax * waistHalf, y: waist.y + ay * waistHalf))
            trunk.addArc(center: hp, radius: hipHalf, startAngle: .radians(atan2(ay, ax)),
                         endAngle: .radians(atan2(ay, ax) + .pi), clockwise: false)
            trunk.addCurve(to: CGPoint(x: ls.x - ax * shoulderR, y: ls.y - ay * shoulderR),
                           control1: CGPoint(x: waist.x - ax * waistHalf, y: waist.y - ay * waistHalf),
                           control2: CGPoint(x: ls.x - ax * shoulderR * 0.9 + down.x * 0.3, y: ls.y - ay * shoulderR * 0.9 + down.y * 0.3))
            trunk.closeSubpath()
            trunk.addPath(disc(ls, shoulderR))
            trunk.addPath(disc(rs, shoulderR))
            draw(trunk)

            // Arms in front, with the elbow as a joint.
            limb(pose.leftShoulder, pose.leftElbow, pose.leftHand, from: 0.042, mid: 0.034, to: 0.024)
            limb(pose.rightShoulder, pose.rightElbow, pose.rightHand, from: 0.042, mid: 0.034, to: 0.024)

            // Neck and head.
            let h = at(pose.head)
            let headR = max(5, unit * shape.headRadius)
            let neckTop = CGPoint(x: neckMid.x + (h.x - neckMid.x) * 0.55, y: neckMid.y + (h.y - neckMid.y) * 0.55)
            draw(capsule(CGPoint(x: (neckMid.x - rect.minX) / rect.width, y: (neckMid.y - rect.minY) / rect.height),
                         CGPoint(x: (neckTop.x - rect.minX) / rect.width, y: (neckTop.y - rect.minY) / rect.height),
                         from: 0.03, to: 0.026))
            let headRect = CGRect(x: h.x - headR * 0.92, y: h.y - headR * 1.08, width: headR * 1.84, height: headR * 2.16)
            draw(Path(ellipseIn: headRect))

            // Hands: small discs on the holds.
            for hand in [pose.leftHand, pose.rightHand] {
                ctx.fill(disc(at(hand), max(3, unit * 0.022 * build)), with: .color(casing))
            }
            // Feet: ringed on a hold, open on a smear.
            for (foot, hold) in [(pose.leftFoot, pose.leftFootHold), (pose.rightFoot, pose.rightFootHold)] {
                let r = max(5, unit * 0.035)
                ctx.stroke(disc(at(foot), r), with: .color(Theme.chalk),
                           style: StrokeStyle(lineWidth: 2.5, dash: hold == nil ? [4, 4] : []))
            }
            _ = edge
        }
        .allowsHitTesting(false)
    }
}

/// Play and scrub through the stances.
struct BetaScrubber: View {
    @Binding var t: Double
    @Binding var playing: Bool
    let stances: Int

    private var stance: Int { min(stances, Int((t * Double(max(stances - 1, 1))).rounded()) + 1) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if t >= 0.999 { t = 0 }
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.button, in: Circle())
            }
            .buttonStyle(.plain)

            Slider(value: $t, in: 0...1) { editing in
                if editing { playing = false }
            }
            .tint(Theme.accent)

            Text("\(stance) of \(stances)")
                .font(Theme.mono(12, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .onReceive(Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()) { _ in
            guard playing else { return }
            // About two seconds a stance.
            t += (1.0 / 30) / (2.0 * Double(max(stances - 1, 1)))
            if t >= 1 { t = 1; playing = false }
        }
    }
}
