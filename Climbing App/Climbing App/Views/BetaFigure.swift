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
            // A silhouette: one solid body, the way a climber reads as a
            // shape against a wall. Every part is drawn into the same ink
            // after every part's casing, so the casing is a single line
            // round the outside and nothing shows through inside.
            let unit = rect.width * span
            let build = shape.shoulderWidth / 0.22
            let ink = Theme.ink
            let casing = Theme.chalk.opacity(0.95)

            func norm(_ p: CGPoint) -> CGPoint {
                CGPoint(x: (p.x - rect.minX) / rect.width, y: (p.y - rect.minY) / rect.height)
            }
            func capsule(_ a: CGPoint, _ b: CGPoint, from wa: Double, to wb: Double) -> Path {
                let p = at(a), q = at(b)
                let dx = q.x - p.x, dy = q.y - p.y
                let len = max(hypot(dx, dy), 0.001)
                let nx = -dy / len, ny = dx / len
                let ra = max(2, unit * wa * build), rb = max(1.5, unit * wb * build)
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
            // A hand or a shoe: a short capsule running on past the joint
            // in the limb's own direction.
            func tip(_ from: CGPoint, _ joint: CGPoint, length: Double, width: Double) -> Path {
                let f = at(from), j = at(joint)
                let dx = j.x - f.x, dy = j.y - f.y
                let len = max(hypot(dx, dy), 0.001)
                let end = CGPoint(x: j.x + dx / len * unit * length, y: j.y + dy / len * unit * length)
                return capsule(joint, norm(end), from: width, to: width * 0.8)
            }

            var parts: [Path] = []
            // Legs, with knees as joints, and shoes.
            for (knee, foot) in [(pose.leftKnee, pose.leftFoot), (pose.rightKnee, pose.rightFoot)] {
                parts.append(capsule(pose.hips, knee, from: 0.052, to: 0.038))
                parts.append(capsule(knee, foot, from: 0.038, to: 0.026))
                parts.append(disc(at(knee), max(2.5, unit * 0.038 * build)))
                parts.append(tip(knee, foot, length: 0.045, width: 0.024))
            }
            // The trunk: shoulders, a waist, hips.
            let ls = at(pose.leftShoulder), rs = at(pose.rightShoulder), hp = at(pose.hips)
            let shoulderR = max(3.5, unit * 0.04 * build)
            let hipHalf = max(4, unit * shape.hipWidth / 2)
            let neckMid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let down = CGPoint(x: hp.x - neckMid.x, y: hp.y - neckMid.y)
            let waist = CGPoint(x: neckMid.x + down.x * 0.62, y: neckMid.y + down.y * 0.62)
            let waistHalf = hipHalf * 0.8
            let across = CGPoint(x: rs.x - ls.x, y: rs.y - ls.y)
            let acrossLen = max(hypot(across.x, across.y), 0.001)
            let ax = across.x / acrossLen, ay = across.y / acrossLen
            var trunk = Path()
            trunk.move(to: CGPoint(x: ls.x - ax * shoulderR, y: ls.y - ay * shoulderR))
            trunk.addLine(to: CGPoint(x: rs.x + ax * shoulderR, y: rs.y + ay * shoulderR))
            trunk.addCurve(to: CGPoint(x: hp.x + ax * hipHalf, y: hp.y + ay * hipHalf),
                           control1: CGPoint(x: rs.x + ax * shoulderR * 0.8 + down.x * 0.35, y: rs.y + ay * shoulderR * 0.8 + down.y * 0.35),
                           control2: CGPoint(x: waist.x + ax * waistHalf, y: waist.y + ay * waistHalf))
            trunk.addArc(center: hp, radius: hipHalf, startAngle: .radians(atan2(ay, ax)),
                         endAngle: .radians(atan2(ay, ax) + .pi), clockwise: false)
            trunk.addCurve(to: CGPoint(x: ls.x - ax * shoulderR, y: ls.y - ay * shoulderR),
                           control1: CGPoint(x: waist.x - ax * waistHalf, y: waist.y - ay * waistHalf),
                           control2: CGPoint(x: ls.x - ax * shoulderR * 0.8 + down.x * 0.35, y: ls.y - ay * shoulderR * 0.8 + down.y * 0.35))
            trunk.closeSubpath()
            parts.append(trunk)
            parts.append(disc(ls, shoulderR))
            parts.append(disc(rs, shoulderR))
            // Arms, with elbows as joints, and hands.
            for (shoulder, elbow, hand) in [(pose.leftShoulder, pose.leftElbow, pose.leftHand),
                                            (pose.rightShoulder, pose.rightElbow, pose.rightHand)] {
                parts.append(capsule(shoulder, elbow, from: 0.036, to: 0.028))
                parts.append(capsule(elbow, hand, from: 0.028, to: 0.02))
                parts.append(disc(at(elbow), max(2, unit * 0.028 * build)))
                parts.append(tip(elbow, hand, length: 0.03, width: 0.02))
            }
            // Neck and head.
            let h = at(pose.head)
            let headR = max(4.5, unit * shape.headRadius)
            let neckTop = CGPoint(x: neckMid.x + (h.x - neckMid.x) * 0.5, y: neckMid.y + (h.y - neckMid.y) * 0.5)
            parts.append(capsule(norm(neckMid), norm(neckTop), from: 0.026, to: 0.024))
            parts.append(Path(ellipseIn: CGRect(x: h.x - headR * 0.9, y: h.y - headR * 1.05, width: headR * 1.8, height: headR * 2.1)))

            for p in parts { ctx.stroke(p, with: .color(casing), style: StrokeStyle(lineWidth: 4, lineJoin: .round)) }
            for p in parts { ctx.fill(p, with: .color(ink)) }

            // A smearing foot is marked, so the difference from a foot on
            // a hold is visible without a legend.
            for (foot, hold) in [(pose.leftFoot, pose.leftFootHold), (pose.rightFoot, pose.rightFootHold)] where hold == nil {
                let r = max(5, unit * 0.035)
                ctx.stroke(disc(at(foot), r), with: .color(Theme.chalk),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }
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
