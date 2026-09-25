import SwiftUI

/// The memory that makes Trace a partner rather than a calculator.
struct ProgressScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    private var tracked: [Climb] {
        store.climbs.filter { $0.metrics.isTrustworthy }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavHeader { dismiss() }
                    header
                    Hairline()

                    if tracked.count < 2 {
                        notEnoughYet
                    } else {
                        // Strengths and weaknesses first. The focus is one thing
                        // to fix; this is the shape of your climbing, and it is
                        // what the rest of the screen is detail on.
                        PatternSection()
                        Hairline()
                        focusSection
                        Hairline()
                        entropyTrend
                        Hairline()
                        signature
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Over time")
                .font(Theme.title(30))
                .foregroundStyle(Theme.ink)
            Text("Is your movement changing?")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private var notEnoughYet: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Not enough tracked climbing yet")
            Text("Trace needs at least two clips it could see clearly before it will claim anything about a trend. One climb is noise.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    // MARK: Focus

    @ViewBuilder
    private var focusSection: some View {
        if let focus = store.focus {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(focus.kind.title)
                    Text(focus.isResolved ? "Cleared" : "What you are working on")
                        .font(Theme.ui(13.5))
                        .foregroundStyle(Theme.ink3)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            MicroLabel(text: "Started")
                            Text(focus.baselineReadout)
                                .font(Theme.ui(16, .medium)).monospacedDigit()
                                .foregroundStyle(Theme.ink2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            MicroLabel(text: "Now")
                            Text(focus.readout)
                                .font(Theme.readout(22)).monospacedDigit()
                                .foregroundStyle(focus.isResolved ? Theme.ok : Theme.accentText)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.surface2).frame(height: 6)
                            Rectangle()
                                .fill(focus.isResolved ? Theme.ok : Theme.accent)
                                .frame(width: geo.size.width * focus.progress, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text(FocusEngine.meaning(for: focus.kind))
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Theme.blueWash)
                .overlay(Rectangle().stroke(Theme.lineStrong, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(text: "Drill", color: Theme.accentText)
                    Text(focus.kind.drill)
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !focus.isResolved {
                    Button {
                        store.dismissFocus()
                    } label: {
                        Text("Work on something else")
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
    }

    // MARK: Entropy trend

    private var entropyTrend: some View {
        let values = tracked.suffix(12).map { $0.metrics.entropy }

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                SectionTitle("Geometric entropy, last \(values.count) climbs")
                Text("Lower is smoother")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
            }

            TrendChart(values: values)
                .frame(height: 150)

            Text(trendSentence(values))
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
    }

    private func trendSentence(_ values: [Double]) -> String {
        guard values.count >= 4 else {
            return "A few more climbs and Trace will call the direction of this."
        }
        let half = values.count / 2
        let early = values.prefix(half).reduce(0, +) / Double(half)
        let late = values.suffix(half).reduce(0, +) / Double(values.count - half)
        let change = early - late

        if change > 0.05 {
            return "Your movement is getting tidier. Entropy is down about \(String(format: "%.2f", change)) from your earlier climbs, which is real rather than noise."
        } else if change < -0.05 {
            return "Entropy is drifting up, which usually means you are climbing closer to your limit rather than climbing worse. Worth checking against the grades you have been on."
        }
        return "Flat so far. Entropy moves when you repeat climbs and refine them, so a session of laps on something familiar will show up here faster than a session of new climbs."
    }

    // MARK: Movement signature

    private var signature: some View {
        let counts = leakCounts()
        let total = max(1, tracked.suffix(12).count)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                SectionTitle("What comes up most")
                Text("Headline finding across your last \(total) climbs")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
            }

            if counts.isEmpty {
                Text("Nothing has crossed the threshold often enough to be a pattern.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.ink2)
            } else {
                VStack(spacing: 1) {
                    ForEach(counts, id: \.kind) { entry in
                        HStack(spacing: 12) {
                            Text(entry.kind.title)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 128, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Theme.surface2).frame(height: 8)
                                    Rectangle()
                                        .fill(entry.kind == store.focus?.kind
                                              ? Theme.accent : Theme.ink3)
                                        .frame(width: geo.size.width
                                               * CGFloat(entry.count) / CGFloat(total),
                                               height: 8)
                                }
                                .frame(height: geo.size.height, alignment: .center)
                            }
                            .frame(height: 16)

                            Text("\(entry.count)")
                                .font(Theme.ui(13, .medium)).monospacedDigit()
                                .foregroundStyle(Theme.ink2)
                                .frame(width: 20, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.surface)
                    }
                }
                .background(Theme.line)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 156)
    }

    private func leakCounts() -> [(kind: LeakKind, count: Int)] {
        var tally: [LeakKind: Int] = [:]
        for climb in tracked.suffix(12) {
            guard let top = climb.findings.first else { continue }
            tally[top.kind, default: 0] += 1
        }
        return tally.map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Trend chart
//
// One series, so no legend: the title names it. Endpoints carry the only value
// labels, because a number on every point is noise.

struct TrendChart: View {
    let values: [Double]

    /// All the geometry, resolved outside the view builder.
    private struct Layout {
        var points: [CGPoint] = []
        var grid: [(value: Double, y: CGFloat)] = []
        var plot: CGRect = .zero
    }

    private func layout(in size: CGSize) -> Layout {
        let leftPad: CGFloat = 40, topPad: CGFloat = 14, bottomPad: CGFloat = 22
        let plotW = max(size.width - leftPad - 10, 1)
        let plotH = max(size.height - topPad - bottomPad, 1)

        let lo = (values.min() ?? 0) - 0.05
        let hi = (values.max() ?? 1) + 0.05
        let span = max(hi - lo, 0.0001)

        func y(_ v: Double) -> CGFloat { topPad + plotH * CGFloat(1 - (v - lo) / span) }

        var out = Layout()
        out.plot = CGRect(x: leftPad, y: topPad, width: plotW, height: plotH)
        out.grid = [lo, lo + span / 2, lo + span].map { ($0, y($0)) }
        out.points = values.enumerated().map { i, v in
            let x = values.count < 2
                ? leftPad + plotW / 2
                : leftPad + plotW * CGFloat(i) / CGFloat(values.count - 1)
            return CGPoint(x: x, y: y(v))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let l = layout(in: geo.size)

            ZStack(alignment: .topLeading) {
                // Recessive grid. Every line names a value the chart actually reaches.
                ForEach(l.grid, id: \.value) { line in
                    Path { p in
                        p.move(to: CGPoint(x: l.plot.minX, y: line.y))
                        p.addLine(to: CGPoint(x: l.plot.maxX, y: line.y))
                    }
                    .stroke(Theme.line, lineWidth: 1)

                    Text(String(format: "%.2f", line.value))
                        .font(Theme.ui(11)).monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                        .position(x: l.plot.minX - 20, y: line.y)
                }

                if l.points.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: l.points[0].x, y: l.plot.maxY))
                        p.addLine(to: l.points[0])
                        for pt in l.points.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: l.points[l.points.count - 1].x, y: l.plot.maxY))
                        p.closeSubpath()
                    }
                    .fill(Theme.accent.opacity(0.10))

                    Path { p in
                        p.move(to: l.points[0])
                        for pt in l.points.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(Theme.accent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Interior points stay quiet; the endpoints carry the emphasis.
                    ForEach(Array(l.points.dropFirst().dropLast()), id: \.self) { pt in
                        Circle().fill(Theme.accent.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .position(pt)
                    }

                    Circle().fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.ground, lineWidth: 2))
                        .position(l.points[0])

                    Circle().fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.ground, lineWidth: 2))
                        .position(l.points[l.points.count - 1])

                    Text(String(format: "%.2f", values[values.count - 1]))
                        .font(Theme.ui(12.5, .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                        .position(x: l.points[l.points.count - 1].x - 18,
                                  y: l.points[l.points.count - 1].y - 14)
                }

                Path { p in
                    p.move(to: CGPoint(x: l.plot.minX, y: l.plot.maxY))
                    p.addLine(to: CGPoint(x: l.plot.maxX, y: l.plot.maxY))
                }
                .stroke(Theme.lineStrong, lineWidth: 1)

                Text("Oldest")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.ink3)
                    .position(x: l.plot.minX + 20, y: l.plot.maxY + 12)
                Text("Latest")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.ink3)
                    .position(x: l.plot.maxX - 20, y: l.plot.maxY + 12)
            }
        }
    }
}
