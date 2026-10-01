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
            // A body, not a wire: limbs with the thickness of limbs, a torso
            // between the shoulders and the hips, a head. Drawn in the live
            // overlay's two inks so it reads as the same idea.
            let limb = max(4, rect.width * span * 0.075)
            let ink = Theme.blue.opacity(0.88)

            let ls = at(pose.leftShoulder), rs = at(pose.rightShoulder), hp = at(pose.hips)
            let hipHalf = max(limb * 0.6, (rs.x - ls.x) * 0.38)
            var torso = Path()
            torso.move(to: ls); torso.addLine(to: rs)
            torso.addLine(to: CGPoint(x: hp.x + hipHalf, y: hp.y))
            torso.addLine(to: CGPoint(x: hp.x - hipHalf, y: hp.y)); torso.closeSubpath()
            ctx.stroke(torso, with: .color(Theme.chalk.opacity(0.95)),
                       style: StrokeStyle(lineWidth: limb + 4, lineJoin: .round))
            ctx.fill(torso, with: .color(ink))
            ctx.stroke(torso, with: .color(ink), style: StrokeStyle(lineWidth: limb, lineJoin: .round))

            for (a, b) in pose.bones where !(a == pose.leftShoulder && b == pose.rightShoulder) {
                var path = Path()
                path.move(to: at(a)); path.addLine(to: at(b))
                ctx.stroke(path, with: .color(Theme.chalk.opacity(0.95)),
                           style: StrokeStyle(lineWidth: limb + 4, lineCap: .round))
                ctx.stroke(path, with: .color(ink),
                           style: StrokeStyle(lineWidth: limb, lineCap: .round))
            }
            let headR = max(5, rect.width * span * shape.headRadius)
            let h = at(pose.head)
            let headRect = CGRect(x: h.x - headR, y: h.y - headR, width: headR * 2, height: headR * 2)
            ctx.stroke(Path(ellipseIn: headRect), with: .color(Theme.chalk.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 4))
            ctx.fill(Path(ellipseIn: headRect), with: .color(ink))

            let w = limb * 0.6
            // Feet: ringed on a hold, open on a smear.
            for (foot, hold) in [(pose.leftFoot, pose.leftFootHold), (pose.rightFoot, pose.rightFootHold)] {
                let q = at(foot)
                let r = w * 1.6
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
