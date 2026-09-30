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

    private func at(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    var body: some View {
        Canvas { ctx, _ in
            let w = max(2.5, rect.width * span * 0.045)
            for (a, b) in pose.bones {
                var path = Path()
                path.move(to: at(a)); path.addLine(to: at(b))
                ctx.stroke(path, with: .color(Theme.chalk.opacity(0.95)),
                           style: StrokeStyle(lineWidth: w + 4, lineCap: .round))
                ctx.stroke(path, with: .color(Theme.blue),
                           style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            let headR = rect.width * span * 0.055
            let h = at(pose.head)
            let headRect = CGRect(x: h.x - headR, y: h.y - headR, width: headR * 2, height: headR * 2)
            ctx.fill(Path(ellipseIn: headRect), with: .color(Theme.chalk))
            ctx.stroke(Path(ellipseIn: headRect.insetBy(dx: 1.5, dy: 1.5)),
                       with: .color(Theme.blue), style: StrokeStyle(lineWidth: w * 0.8))

            for p in pose.joints {
                let q = at(p)
                let r = w * 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.chalk))
            }
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
