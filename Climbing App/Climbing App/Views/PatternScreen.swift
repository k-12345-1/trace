import SwiftUI

/// Where your climbing is strong and where it is not, read across routes.
///
/// The order is deliberate and it is not flattering: weakest first. A screen
/// that opens with what you are good at buries the one thing you came for.
struct PatternSection: View {
    @ObservedObject private var store = Store.shared

    private var report: PatternEngine.Report? {
        PatternEngine.report(from: store.climbs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                SectionTitle("Where you stand")
                Text(subtitle)
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let report {
                VStack(spacing: 8) {
                    ForEach(report.readings) { reading in
                        row(reading)
                    }
                }

                if let smoothness = report.smoothness {
                    smoothnessNote(smoothness)
                }

                footnote(report)
            } else {
                waiting
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        guard let report else { return "Across the routes you have climbed" }
        return "Across \(report.routes) routes, best attempt on each"
    }

    // MARK: One dimension

    private func row(_ r: PatternEngine.Reading) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // The ramp runs light to dark with cost, so the weakest dimension is
            // the darkest mark on the page. It never carries the meaning alone:
            // the word is right beside it.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(r.standing))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(r.kind.title)
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(r.standing.label)
                        .font(Theme.ui(12.5, .semibold))
                        .foregroundStyle(color(r.standing))
                    Text(r.display)
                        .font(Theme.ui(12.5)).monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                    if let d = r.direction, d != .flat {
                        Text(d == .improving ? "improving" : "slipping")
                            .font(Theme.ui(12.5, .medium))
                            .foregroundStyle(Theme.ink2)
                    }
                }

                Text("\(r.routes) route\(r.routes == 1 ? "" : "s")")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func color(_ s: PatternEngine.Standing) -> Color {
        switch s {
        case .strong:  return Theme.ember[0]
        case .solid:   return Theme.ember[1]
        case .working: return Theme.ember[3]
        case .weak:    return Theme.ember[4]
        }
    }

    // MARK: Smoothness, which has no standing

    private func smoothnessNote(_ d: PatternEngine.Direction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Smoothness")
                .font(Theme.ui(14, .semibold))
                .foregroundStyle(Theme.ink)
            Text(smoothnessText(d))
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private func smoothnessText(_ d: PatternEngine.Direction) -> String {
        let where_ = d == .improving ? "getting smoother"
                   : d == .slipping ? "getting more start-stop" : "about where it was"
        return "Your movement is \(where_). This one has no standing beside it on purpose: the measurement is swamped by the pose tracker's own noise, so there is no value at which anyone is simply smooth. It is only ever compared to your own earlier climbing."
    }

    // MARK: Honesty

    private func footnote(_ r: PatternEngine.Report) -> some View {
        Text("Measured against the same numbers that flag a single climb, not against other climbers: Trace has no one to compare you to. One attempt per route, the best one, so a problem you worked all session does not outvote the rest.")
            .font(Theme.ui(12))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(waitingText)
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .card()
    }

    private var waitingText: String {
        let have = PatternEngine.distinctRoutes(store.climbs)
        let need = PatternEngine.minimumRoutes - have
        if have == 0 {
            return "Climb a few different routes and Trace will start telling you where your movement is strong and where it is not. It needs \(PatternEngine.minimumRoutes) to say anything."
        }
        return "\(have) route\(have == 1 ? "" : "s") so far. \(need) more and Trace will read your movement across them. It counts routes rather than attempts, because ten goes at one problem mostly measure how tired you got on it."
    }
}
