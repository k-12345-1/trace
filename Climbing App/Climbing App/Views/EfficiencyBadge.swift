import SwiftUI

/// The efficiency grade: five steps, worst to best.
///
/// The color never carries the meaning on its own. The word is always beside
/// it and the filled steps are always countable, so the grade survives being
/// read by someone who cannot tell the ends of the ramp apart, and survives
/// being printed in grey.
struct EfficiencyBadge: View {
    let reading: EfficiencyEngine.Reading
    var compact = false

    private var tint: Color {
        Theme.efficiency[min(max(reading.grade.rawValue - 1, 0), Theme.efficiency.count - 1)]
    }

    var body: some View {
        if compact {
            HStack(spacing: 7) {
                steps(height: 12, width: 5)
                Text(reading.grade.label)
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(tint)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(reading.grade.label)
                        .font(Theme.serif(22, .semibold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    Text("\(reading.grade.rawValue) of 5")
                        .font(Theme.ui(12.5, .medium)).monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                }
                steps(height: 10, width: nil)
            }
        }
    }

    /// Five blocks, the first N filled. Countable, so the grade is legible
    /// without the color being legible.
    private func steps(height: CGFloat, width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(i <= reading.grade.rawValue ? tint : Theme.surface2)
                    .frame(width: width, height: height)
                    .frame(maxWidth: width == nil ? .infinity : nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Efficiency \(reading.grade.rawValue) of 5, \(reading.grade.label)")
    }
}

/// The grade with its working shown.
struct EfficiencyCard: View {
    let reading: EfficiencyEngine.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("How efficient it was")
            EfficiencyBadge(reading: reading)

            if let worst = reading.worst, worst.contribution > 0.02 {
                Text("Most of it was \(worst.name.lowercased()): \(worst.detail).")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 7) {
                ForEach(reading.components) { part in
                    HStack(spacing: 10) {
                        Text(part.name)
                            .font(Theme.ui(13))
                            .foregroundStyle(Theme.ink2)
                            .frame(width: 106, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surface2).frame(height: 6)
                                Capsule().fill(Theme.ink3)
                                    .frame(width: max(2, geo.size.width * part.cost), height: 6)
                            }
                            .frame(height: geo.size.height, alignment: .center)
                        }
                        .frame(height: 14)
                        Text(part.detail)
                            .font(Theme.ui(11.5))
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 112, alignment: .trailing)
                            .lineLimit(2)
                    }
                }
            }

            Text(EfficiencyEngine.caveat)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .card()
    }
}
