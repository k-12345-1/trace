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
    @State private var choosingGym = false
    @Environment(\.dismiss) private var dismiss

    /// Read back out of the store so a rename or a send shows at once.
    private var live: LibraryEntry {
        store.library().first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photo
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        attempts
                        analysis
                        physics
                        // Inside the card, not under it. The clearance for the
                        // bar used to sit outside this, which left a band of
                        // bare paper between the last thing on the page and the
                        // bottom of the screen: the page appeared to stop, and
                        // then there was more page.
                        Color.clear.frame(height: 156)
                    }
                    .background(Theme.ground)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.top, -28)
                }
            }
            .scrollIndicators(.hidden)
            // Without this the photo stops at the safe area and the clock and
            // battery sit on a white strip above it. The back control is already
            // padded down to clear them.
            .ignoresSafeArea(edges: .top)
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

    private static let photoHeight: CGFloat = 330

    /// The photograph, which grows rather than slides when the page is pulled
    /// down.
    ///
    /// A scroll view bounces at the top whatever you do, and what a bounce
    /// used to reveal here was a band of bare paper above the picture: the one
    /// place on this screen with nothing in it, shown by the one gesture
    /// everybody makes without meaning to. Stretching the picture into that
    /// space is what every photo header does, and it costs one measurement.
    private var photo: some View {
        GeometryReader { geo in
            let pulled = max(0, geo.frame(in: .scrollView).minY)
            ClimbThumbnail(climb: live.latest)
                .frame(width: geo.size.width, height: Self.photoHeight + pulled)
                .offset(y: -pulled)
        }
        .frame(height: Self.photoHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) { back }
    }

    /// The photo runs under the status bar, so the way out has to sit on top of it.
    private var back: some View {
        BackOverlayButton { dismiss() }
            .padding(.leading, Theme.gutter - 6)
            .padding(.top, 54)
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

            whereItWas

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
                            // The grade rather than the raw numbers. Comparing
                            // two attempts on one route is the reason this list
                            // exists, and an entropy figure does not do that at
                            // a glance.
                            if let reading = EfficiencyCache.read(climb) {
                                EfficiencyBadge(reading: reading, compact: true)
                            } else {
                                Text("H \(String(format: "%.2f", climb.metrics.entropy))")
                                    .font(Theme.ui(13))
                                    .foregroundStyle(Theme.ink3)
                            }
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

    /// Which gym this route is at, and a way to say so.
    ///
    /// Every climb recorded before Trace asked has no gym, and there is no
    /// honest way to work one out afterwards: the footage shows a wall, not an
    /// address. So it is asked rather than guessed, once, and answering applies
    /// to every attempt on the route.
    private var whereItWas: some View {
        let gym = store.gyms.first { $0.id == live.latest.gymID }
        return Button { choosingGym = true } label: {
            HStack(spacing: 9) {
                Image(systemName: gym == nil ? "mappin.slash" : "mappin.and.ellipse")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink3)
                Text(gym?.name ?? "Not filed at a gym")
                    .font(Theme.ui(14, gym == nil ? .regular : .semibold))
                    .foregroundStyle(gym == nil ? Theme.ink3 : Theme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(gym == nil ? "Choose" : "Change")
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter)
        .confirmationDialog("Which gym?", isPresented: $choosingGym, titleVisibility: .visible) {
            ForEach(store.gyms) { g in
                Button(g.name) { store.setGym(g.id, for: live.latest) }
            }
            if live.latest.gymID != nil {
                Button("Not at a gym", role: .destructive) { store.setGym(nil, for: live.latest) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(store.gyms.isEmpty
                 ? "You have no gyms yet. Add one from Explore or by scanning a route."
                 : "This applies to every attempt on this route.")
        }
    }

    /// The lowest-entropy attempt Trace could trust, which is the one worth
    /// quoting: it is the closest you have come to doing this route well.
    private var bestMeasured: Climb? {
        live.measured.min { $0.metrics.entropy < $1.metrics.entropy }
    }


    // MARK: What the movement showed

    /// The observations, each with the mechanics that make it worth acting on.
    ///
    /// This used to be headed "The physics", which put the lecture in front of
    /// the finding. The physics has not gone anywhere and nothing has been
    /// softened: it sits inside each observation, where it is the reason the
    /// observation costs you something rather than a topic of its own.
    private var physics: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("What the movement showed")
                .padding(.horizontal, Theme.gutter)

            if notes.isEmpty {
                Text("Nothing on this route crossed the threshold worth mentioning. The measurements above still stand; there is just no leak to explain.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)
            } else {
                VStack(spacing: 12) {
                    ForEach(notes, id: \.0) { title, note in
                        ObservationCard(
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
                    .foregroundStyle(Theme.ink2)
                    .underline()
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
/// One thing Trace saw, and the mechanics that make it worth changing.
///
/// The observation is the headline. Closed, the card says what happened and
/// names the idea it rests on. Opened, it gives the mechanics, the relationship
/// they come from, and what was actually measured to say any of it. The
/// formula used to sit on the front of the card, which made every finding look
/// like a physics lesson with a climb attached.
private struct ObservationCard: View {
    let title: String
    let note: PhysicsNote
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(Theme.serif(17.5, .semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        // Plain words, always visible, no term of art and no
                        // formula. Nobody has to open anything to know what to
                        // do about this.
                        Text(note.plain)
                            .font(Theme.ui(14.5))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // The rigor is still all here. It is one tap down instead of first,
            // so the finding is readable without it and provable with it.
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Text(open ? "Hide the mechanics" : "Why this is true")
                        .font(Theme.ui(13.5, .semibold))
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                Text(note.concept)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.blueLight)

                Text(note.why)
                    .font(Theme.ui(14.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("The relationship")
                        .font(Theme.ui(13, .semibold))
                        .foregroundStyle(Theme.ink2)
                    Text(note.law)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.blueWash)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                }

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
