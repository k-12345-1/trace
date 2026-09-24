import SwiftUI

/// One route: the photo, the count, the analysis, and the mechanics underneath it.
///
/// This sits between the library and a single attempt. The library is a list of
/// routes, an attempt is one clip, and this is the route itself: everything you
/// have done on it, what Trace found across all of it, and why each of those
/// findings costs you something.
struct ClimbCardScreen: View {
    let entry: LibraryEntry

    @ObservedObject private var store = Store.shared
    @State private var renaming = false
    @State private var draftName = ""
    @State private var expanded: Set<String> = []
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    /// Read back out of the store so a rename or a send shows at once.
    private var live: LibraryEntry {
        store.library().first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photo
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        attempts
                        analysis
                        physics
                    }
                    .background(Theme.ground)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.top, -28)
                }
                .padding(.bottom, 96)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .alert("Route name", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") { store.rename(live, to: draftName) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Renaming applies to every attempt on this route.")
        }
        .alert("Delete this route?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { store.delete(live); dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(live.attemptCount) attempt\(live.attemptCount == 1 ? "" : "s") and their clips go with it.")
        }
    }

    // MARK: Photo of the climb

    private var photo: some View {
        ClimbThumbnail(climb: live.latest)
            .frame(height: 330)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) { back }
    }

    /// The photo runs under the status bar, so the way out has to sit on top of it.
    private var back: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(.black.opacity(0.32)))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.gutter - 4)
        .padding(.top, 56)
    }

    // MARK: Name and counts

    private var heading: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(live.name)
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    draftName = live.name == "Untitled climb" ? "" : live.name
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }

            if let top = live.topFinding {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.ember[min(top.severity.rawValue, Theme.ember.count - 1)])
                        .frame(width: 9, height: 9)
                    Text(top.severity.label)
                        .font(Theme.ui(15))
                        .foregroundStyle(Theme.ink2)
                    Text("·").foregroundStyle(Theme.ink3)
                    Text(top.kind.title)
                        .font(Theme.ui(15))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
            }

            MetricStrip(items: [
                .init(value: "\(live.attemptCount)", label: live.attemptCount == 1 ? "Attempt" : "Attempts"),
                .init(value: "\(live.sendCount)", label: live.sendCount == 1 ? "Send" : "Sends"),
                .init(value: "\(daysOn)", label: daysOn == 1 ? "Day" : "Days"),
                .init(value: bestEntropy, label: "Best H")
            ])
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 26)
        .padding(.bottom, 24)
    }

    private var bestEntropy: String {
        guard let best = bestMeasured else { return "—" }
        return String(format: "%.2f", best.metrics.entropy)
    }

    /// Distinct calendar days on which this route was climbed.
    private var daysOn: Int {
        Set(live.attempts.map { Calendar.current.startOfDay(for: $0.recordedAt) }).count
    }

    // MARK: Attempts

    private var attempts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Attempts")
                .padding(.horizontal, Theme.gutter)

            VStack(spacing: 4) {
                ForEach(live.attempts.sorted { $0.recordedAt > $1.recordedAt }) { climb in
                    attemptRow(climb)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 26)
        }
    }

    private func attemptRow(_ climb: Climb) -> some View {
        HStack(spacing: 12) {
            NavigationLink { ResultsScreen(climb: climb) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(climb.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.ui(15, .medium))
                            .foregroundStyle(Theme.ink)
                        if climb.metrics.isTrustworthy {
                            Text("H \(String(format: "%.2f", climb.metrics.entropy)) · \(Int(climb.metrics.staticElbowAngle.rounded()))° elbows")
                                .font(Theme.ui(13))
                                .foregroundStyle(Theme.ink3)
                        } else {
                            Text("Low tracking")
                                .font(Theme.ui(13))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Marking a send is a tap, not a menu. It is the thing you do most.
            Button { store.toggleSent(climb) } label: {
                Image(systemName: climb.isSent ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(climb.isSent ? Theme.accent : Theme.lineStrong)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card()
    }

    // MARK: Movement analysis

    private var analysis: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Movement analysis")
                .padding(.horizontal, Theme.gutter)

            if let best = bestMeasured {
                ReadoutGrid {
                    Readout(label: "Entropy", value: String(format: "%.2f", best.metrics.entropy),
                            unit: "H", hint: "lower is straighter")
                    Readout(label: "Smoothness", value: String(format: "%.1f", best.metrics.logJerk),
                            unit: "log jerk", hint: "lower is smoother")
                    Readout(label: "Static elbows",
                            value: "\(Int(best.metrics.staticElbowAngle.rounded()))",
                            unit: "deg", hint: "180 is straight")
                    Readout(label: "Stops", value: "\(best.metrics.pauseCount)",
                            unit: String(format: "%.1f s", best.metrics.pauseTotal),
                            hint: "while hanging on")
                }
                .padding(.horizontal, Theme.gutter)

                Text("From your \(ordinalBest) attempt, the cleanest one Trace could track.")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, Theme.gutter)
            } else {
                Text("Trace could not track any attempt on this route well enough to measure it. Film side on, with the whole boulder in frame.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.bottom, 28)
    }

    /// The lowest-entropy attempt Trace could trust, which is the one worth
    /// quoting: it is the closest you have come to doing this route well.
    private var bestMeasured: Climb? {
        live.measured.min { $0.metrics.entropy < $1.metrics.entropy }
    }

    private var ordinalBest: String {
        guard let best = bestMeasured else { return "last" }
        let order = live.attempts.sorted { $0.recordedAt < $1.recordedAt }
        guard let i = order.firstIndex(where: { $0.id == best.id }) else { return "last" }
        let n = i + 1
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        default: return "\(n)th"
        }
    }

    // MARK: The physics

    private var physics: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("The physics")
                Text("What each of these is standing on")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, Theme.gutter)

            if notes.isEmpty {
                Text("Nothing was flagged on this route, so there is nothing to explain. The numbers above are defined under Entropy and Smoothness on any attempt Trace could track.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)
            } else {
                VStack(spacing: 12) {
                    ForEach(notes, id: \.0) { title, note in
                        PhysicsCard(
                            title: title,
                            note: note,
                            open: expanded.contains(title),
                            toggle: {
                                if expanded.contains(title) { expanded.remove(title) }
                                else { expanded.insert(title) }
                            }
                        )
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }

            Button(role: .destructive) { confirmingDelete = true } label: {
                Text("Delete this route")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.ember[4])
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 20)
        }
        .padding(.top, 8)
    }

    /// One note per distinct leak found anywhere on this route, worst first.
    private var notes: [(String, PhysicsNote)] {
        var worst: [LeakKind: Severity] = [:]
        for climb in live.attempts {
            for finding in climb.findings {
                if let current = worst[finding.kind] {
                    worst[finding.kind] = max(current, finding.severity)
                } else {
                    worst[finding.kind] = finding.severity
                }
            }
        }
        // Worst first, then by title. Without the second key the order comes
        // out of a dictionary and reshuffles every time the view recomputes.
        return worst
            .sorted {
                $0.value.rawValue != $1.value.rawValue
                    ? $0.value.rawValue > $1.value.rawValue
                    : $0.key.title < $1.key.title
            }
            .map { ($0.key.title, $0.key.physics) }
    }
}

// MARK: - One explanation

/// Collapsed to its concept, because a wall of mechanics is not what you want
/// while you are still looking at the photo. The law is always visible: it is
/// one line and it is the part worth remembering.
private struct PhysicsCard: View {
    let title: String
    let note: PhysicsNote
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(Theme.ui(16, .bold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Text(note.concept)
                            .font(Theme.ui(13, .medium))
                            .foregroundStyle(Theme.blueLight)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(note.law)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.blueWash)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))

            if open {
                Text(note.why)
                    .font(Theme.ui(14.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("What Trace measured")
                        .font(Theme.ui(13, .semibold))
                        .foregroundStyle(Theme.ink2)
                    Text(note.measured)
                        .font(Theme.ui(13.5))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
