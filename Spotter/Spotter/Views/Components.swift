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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(Theme.readout(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if let unit {
                    Text(unit)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink3)
                }
            }
            if let delta {
                Text(delta)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(deltaIsWork ? Theme.accentText : Theme.ok)
            }
        }
        // maxHeight so every tile in a row fills it. Without this a tile carrying a
        // delta line makes its neighbour float in a half-filled cell.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }
}

/// Readouts sit in a hairline grid, not in separate rounded cards.
struct ReadoutGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)],
            spacing: 1
        ) { content }
        .background(Theme.line)
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
    }
}

// MARK: - Finding

struct FindingCard: View {
    let finding: Finding
    var showDrill: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(finding.timecode)\(finding.duration > 0.5 ? " · \(String(format: "%.1f", finding.duration)) S" : "")")
                    .font(Theme.mono(10.5))
                    .tracking(0.6)
                    .foregroundStyle(Theme.accentText)
                Spacer(minLength: 0)
                SeverityChip(severity: finding.severity)
            }

            Text(finding.kind.title)
                .font(Theme.heading(17))
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
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(width: 3)
        }
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
    }
}

struct SeverityChip: View {
    let severity: Severity
    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Theme.ember[min(severity.rawValue, Theme.ember.count - 1)])
                .frame(width: 7, height: 7)
            Text(severity.label.uppercased())
                .font(Theme.mono(9.5, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .overlay(RoundedRectangle(cornerRadius: Theme.rSmall).stroke(Theme.lineStrong, lineWidth: 1))
    }
}

// MARK: - Status chip

struct StatusChip: View {
    let text: String
    var dot: Color = Theme.ok
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text.uppercased())
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.surface.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: Theme.rSmall).stroke(Theme.lineStrong, lineWidth: 1))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.mono(11, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(filled ? Theme.ground : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(filled ? Theme.accent : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.r)
                        .stroke(filled ? Color.clear : Theme.lineStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
