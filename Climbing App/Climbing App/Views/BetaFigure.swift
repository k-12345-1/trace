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
            // A body, not a wire. Every width is this climber's own where
            // their footage has been read: shoulders, hips, and limbs that
            // thicken toward the trunk the way limbs do. Drawn in the live
            // overlay's two inks so it reads as the same idea.
            let unit = rect.width * span
            let build = shape.shoulderWidth / 0.22
            let ink = Theme.blue.opacity(0.9)
            let casing = Theme.chalk.opacity(0.95)

            func limb(_ a: CGPoint, _ b: CGPoint, from wa: Double, to wb: Double) {
                // A tapered capsule: wide at the trunk end, narrower at the
                // hand or foot.
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
                ctx.stroke(path, with: .color(casing), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                ctx.fill(path, with: .color(ink))
            }

            // Legs behind the trunk, arms in front, head last.
            limb(pose.hips, pose.leftKnee, from: 0.055, to: 0.04)
            limb(pose.leftKnee, pose.leftFoot, from: 0.04, to: 0.028)
            limb(pose.hips, pose.rightKnee, from: 0.055, to: 0.04)
            limb(pose.rightKnee, pose.rightFoot, from: 0.04, to: 0.028)

            let ls = at(pose.leftShoulder), rs = at(pose.rightShoulder), hp = at(pose.hips)
            let hipHalf = max(4, unit * shape.hipWidth / 2)
            let shoulderPad = max(3, unit * 0.03 * build)
            var torso = Path()
            torso.move(to: CGPoint(x: ls.x - shoulderPad, y: ls.y))
            torso.addLine(to: CGPoint(x: rs.x + shoulderPad, y: rs.y))
            torso.addLine(to: CGPoint(x: hp.x + hipHalf, y: hp.y + hipHalf * 0.5))
            torso.addLine(to: CGPoint(x: hp.x - hipHalf, y: hp.y + hipHalf * 0.5))
            torso.closeSubpath()
            ctx.stroke(torso, with: .color(casing), style: StrokeStyle(lineWidth: max(6, unit * 0.04), lineJoin: .round))
            ctx.fill(torso, with: .color(ink))
            ctx.stroke(torso, with: .color(ink), style: StrokeStyle(lineWidth: max(4, unit * 0.03), lineJoin: .round))

            limb(pose.leftShoulder, pose.leftElbow, from: 0.038, to: 0.03)
            limb(pose.leftElbow, pose.leftHand, from: 0.03, to: 0.02)
            limb(pose.rightShoulder, pose.rightElbow, from: 0.038, to: 0.03)
            limb(pose.rightElbow, pose.rightHand, from: 0.03, to: 0.02)

            // Neck and head.
            let neck = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let h = at(pose.head)
            var neckPath = Path(); neckPath.move(to: neck); neckPath.addLine(to: h)
            ctx.stroke(neckPath, with: .color(casing), style: StrokeStyle(lineWidth: max(7, unit * 0.045), lineCap: .round))
            ctx.stroke(neckPath, with: .color(ink), style: StrokeStyle(lineWidth: max(4, unit * 0.03), lineCap: .round))
            let headR = max(5, unit * shape.headRadius)
            let headRect = CGRect(x: h.x - headR, y: h.y - headR, width: headR * 2, height: headR * 2)
            ctx.stroke(Path(ellipseIn: headRect), with: .color(casing), style: StrokeStyle(lineWidth: 3))
            ctx.fill(Path(ellipseIn: headRect), with: .color(ink))

            // Hands: small rings on the holds.
            for hand in [pose.leftHand, pose.rightHand] {
                let q = at(hand), r = max(3, unit * 0.022 * build)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(casing))
            }
            // Feet: ringed on a hold, open on a smear.
            for (foot, hold) in [(pose.leftFoot, pose.leftFootHold), (pose.rightFoot, pose.rightFootHold)] {
                let q = at(foot)
                let r = max(5, unit * 0.035)
                let ring = Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2))
                ctx.stroke(ring, with: .color(Theme.chalk),
                           style: StrokeStyle(lineWidth: 2.5, dash: hold == nil ? [4, 4] : []))
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
