import SwiftUI

// MARK: - Readout tile
//
// Every metric, timestamp, angle and grade is tabular mono. It is what makes the
// app read as a measuring device rather than a feed.

struct Readout: View {
    let label: String
    let value: String
    var unit: String? = nil
    var delta: String? = nil
    var deltaIsWork: Bool = false
    /// A note on how to read the number. Not a judgement, so it never takes the
    /// colour that a delta does.
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(Theme.ui(27, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if let unit {
                    Text(unit)
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            if let delta {
                Text(delta)
                    .font(Theme.ui(12.5, .medium))
                    .foregroundStyle(deltaIsWork ? Theme.accentText : Theme.ok)
            }
            if let hint {
                Text(hint)
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
        // maxHeight so every tile in a row fills it. Without this a tile carrying a
        // delta line makes its neighbour float in a half-filled cell.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .card()
    }
}

/// Readouts sit apart from each other, with the gap doing the separating.
struct ReadoutGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) { content }
    }
}

// MARK: - Finding

struct FindingCard: View {
    let finding: Finding
    var showDrill: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(finding.timecode)\(finding.duration > 0.5 ? " · \(String(format: "%.1f", finding.duration))s" : "")")
                    .font(Theme.ui(12.5, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.accentText)
                Spacer(minLength: 0)
                SeverityChip(severity: finding.severity)
            }

            Text(finding.kind.title)
                .font(Theme.serif(18, .semibold))
                .foregroundStyle(Theme.ink)

            Text(finding.message)
                .font(Theme.body(14.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if showDrill {
                VStack(alignment: .leading, spacing: 5) {
                    MicroLabel(text: "Drill", color: Theme.accentText)
                    Text(finding.kind.drill)
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(Theme.accent).frame(width: 3, height: 34).padding(.leading, 6)
        }
    }
}

struct SeverityChip: View {
    let severity: Severity
    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Theme.ember[min(severity.rawValue, Theme.ember.count - 1)])
                .frame(width: 7, height: 7)
            Text(severity.label)
                .font(Theme.ui(12.5, .medium))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.surface2)
        .clipShape(Capsule())
    }
}

// MARK: - Status chip

struct StatusChip: View {
    let text: String
    var dot: Color = Theme.ok
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text)
                .font(Theme.ui(12.5, .medium))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Theme.ground.opacity(0.92))
        .clipShape(Capsule())
    }
}

// MARK: - Buttons

/// The only fully round thing in the app.
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.lineStrong, lineWidth: 2).frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: isRecording ? 4 : 26)
                    .fill(Theme.accent)
                    .frame(width: isRecording ? 30 : 52, height: isRecording ? 30 : 52)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record a climb")
    }
}

struct FlatButton: View {
    let title: String
    var filled: Bool = false
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(Theme.ui(16, .semibold))
            }
            .foregroundStyle(filled ? .white : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(filled ? Theme.accent : Theme.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric strip

/// Four numbers across, split by hairlines. The pattern every outdoor app uses
/// for length, gain, time and shape, because it reads in one glance and costs
/// one line of vertical space.
struct MetricStrip: View {
    struct Item: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }
    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 {
                    Rectangle().fill(Theme.line).frame(width: 1, height: 34)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.value)
                        .font(Theme.ui(19, .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.label)
                        .font(Theme.ui(12.5, .regular))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, i > 0 ? 14 : 0)
            }
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let micro: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: micro)
            Text(title)
                .font(Theme.heading(19))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
