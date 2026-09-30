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
    /// A note on how to read the number. Not a judgment, so it never takes the
    /// color that a delta does.
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

/// One finding: the moment it happened, what it was, and the frame it happened
/// in.
///
/// The frame does most of the work. A sentence about bent arms is an assertion
/// and the picture of them bent is evidence, so the picture leads and the prose
/// gets shorter. The drill folds away, because you want it when you are
/// deciding what to do next and not while you are reading what happened.
struct FindingCard: View {
    let finding: Finding
    var showDrill: Bool = true
    /// The climb it came from, for pulling the frame. Optional so the card
    /// still works anywhere the clip is not to hand.
    var climb: Climb? = nil

    @State private var still: UIImage?
    @State private var drillOpen = false
    @ObservedObject private var store = Store.shared

    /// The live copy, so a thumb shows as pressed the moment it is.
    private var current: Finding {
        guard let climb else { return finding }
        return store.climbs.first { $0.id == climb.id }?
            .findings.first { $0.id == finding.id } ?? finding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let still {
                // Cropped to the climber and marked, rather than a wide band of
                // wall with a small figure somewhere in it. The crop and the
                // marks are both worked out from the tracking, so what is drawn
                // lands on what it is describing.
                FindingStill(image: still, finding: finding, climb: climb)
            }

            VStack(alignment: .leading, spacing: 8) {
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
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                // What to do, in one line, without opening anything. The drill
                // below is for later; this is for the next move, and it is the
                // thing somebody looking at a picture of their own mistake
                // actually wants.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.top, 2)
                    Text(finding.kind.instead)
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)

                // Was this any use? Asked on every finding, because a finding
                // the climber disagrees with is the most useful thing Trace
                // can learn about its own thresholds.
                if let climb {
                    HStack(spacing: 6) {
                        Text("Helpful?")
                            .font(Theme.ui(12.5))
                            .foregroundStyle(Theme.ink3)
                        Spacer(minLength: 0)
                        thumb(up: true, climb: climb)
                        thumb(up: false, climb: climb)
                    }
                    .padding(.top, 6)
                }

                if showDrill {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { drillOpen.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Text(drillOpen ? "Hide the drill" : "What to do about it")
                                .font(Theme.ui(13, .semibold))
                            Image(systemName: drillOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if drillOpen {
                        Text(finding.kind.drill)
                            .font(Theme.body(13.5))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .task {
            guard let climb, still == nil,
                  // The best-tracked moment in the window rather than its
                  // middle, and the same instant the marks are drawn from, so
                  // the picture and the lines are of the same moment.
                  let at = FindingStill.instant(for: finding, in: climb) else { return }
            still = await Thumbnails.frame(of: climb, at: at)
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
                // The same ring and the same white disc the scan shutter
                // draws, because they are the same act: point the phone at the
                // wall and press the round button. A blue disc here and a white
                // one there made two screens that do one thing look like two
                // different apps. What it does differently is what it does
                // differently: the disc pulls into a square while it records.
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: isRecording ? 5 : 29, style: .continuous)
                    .fill(.white)
                    .frame(width: isRecording ? 30 : 58, height: isRecording ? 30 : 58)
            }
            // The whole circle, and a bit more, is the target.
            //
            // A plain button hit-tests what it draws, and what this drew was a
            // thin ring and a filled square inside it. Tapping the ring, which
            // is most of what you can see, hit nothing at all, and once
            // recording the only live target was the thirty point stop square.
            .frame(width: 84, height: 84)
            .contentShape(Circle())
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
            .background(filled ? Theme.button : Theme.surface)
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
    /// Where each column's number and label sit inside it. Leading on a route,
    /// which reads as a row of readings under a heading; centred on the profile,
    /// where it is the only thing on its line and has no column to hang off.
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 {
                    Rectangle().fill(Theme.line).frame(width: 1, height: 34)
                }
                VStack(alignment: alignment, spacing: 4) {
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
                .frame(maxWidth: .infinity,
                       alignment: alignment == .center ? .center : .leading)
                .padding(.leading, alignment == .center ? 0 : (i > 0 ? 14 : 0))
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


/// A wrapping row of small tappable chips. Used for timecodes that seek the
/// clip, where a list would be six lines for six numbers.
struct FlowOfChips: View {
    let items: [(String, () -> Void)]

    init(_ items: [(String, () -> Void)]) { self.items = items }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button(action: item.1) {
                        Text(item.0)
                            .font(Theme.ui(12.5, .medium)).monospacedDigit()
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Theme.surface, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
            // Only up and down. A row whose contents already fit still
            // takes a sideways drag and rubber-bands, which on a page that
            // scrolls vertically reads as the page itself coming loose.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}


extension FindingCard {
    fileprivate func thumb(up: Bool, climb: Climb) -> some View {
        let on = current.helpful == up
        return Button {
            store.rate(finding, in: climb, helpful: up)
        } label: {
            Image(systemName: up ? "hand.thumbsup" : "hand.thumbsdown")
                .symbolVariant(on ? .fill : .none)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.accentText)
                .frame(width: 34, height: 30)
                .background(on ? Theme.button : Theme.surface2,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up ? "Helpful" : "Not helpful")
    }
}
