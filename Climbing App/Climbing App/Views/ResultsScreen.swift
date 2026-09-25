import SwiftUI
import AVFoundation

// MARK: - Playback

@MainActor
final class PlaybackModel: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    /// How fast it plays. A deadpoint is over in tens of milliseconds and a
    /// foot placement is barely longer, so full speed is the wrong speed for
    /// most of what this screen is pointing at.
    @Published private(set) var rate: Float = 1

    static let rates: [Float] = [1, 0.5, 0.25]

    let player: AVPlayer
    private var observer: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            Task { @MainActor in self?.time = t.seconds }
        }
        Task { await loadDuration() }
    }

    private func loadDuration() async {
        guard let item = player.currentItem else { return }
        let d = try? await item.asset.load(.duration)
        duration = d?.seconds ?? 0
    }

    func toggle() {
        if isPlaying { player.pause() } else {
            if time >= duration - 0.05 { seek(to: 0) }
            // Setting rate is what starts it. `play()` would run at 1 and then
            // jump to the chosen speed on the next frame.
            player.rate = rate
        }
        isPlaying.toggle()
    }

    /// Round the speeds, staying wherever the video already is.
    func cycleRate() {
        let i = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(i + 1) % Self.rates.count]
        if isPlaying { player.rate = rate }
    }

    /// One frame at a time, for the moment a slow speed still goes past.
    func step(_ frames: Int) {
        if isPlaying { player.pause(); isPlaying = false }
        player.currentItem?.step(byCount: frames)
        if let t = player.currentItem?.currentTime().seconds { time = t }
    }

    func seek(to t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        time = t
    }

    deinit { if let observer { player.removeTimeObserver(observer) } }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ uiView: LayerView, context: Context) {}

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Results

struct ResultsScreen: View {
    let climb: Climb
    var onClose: (() -> Void)? = nil

    @StateObject private var playback: PlaybackModel
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var aspect: Double = 9.0 / 16.0
    @State private var showAllFindings = false
    @State private var renaming = false
    @State private var draftLabel = ""

    /// Read the label back out of the store so a rename shows immediately.
    private var label: String {
        let current = store.climbs.first { $0.id == climb.id }?.label ?? climb.label
        return current.isEmpty ? "Untitled climb" : current
    }

    init(climb: Climb, onClose: (() -> Void)? = nil) {
        self.climb = climb
        self.onClose = onClose
        _playback = StateObject(wrappedValue: PlaybackModel(url: climb.videoURL))
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The footage is the header. It runs to both edges and to
                    // the very top of the screen, under the status bar, with the
                    // back control floating on it.
                    stage
                    header
                    telemetry
                    scrubber
                    Hairline()
                    if climb.metrics.isTrustworthy {
                        ending
                        headline
                        Hairline()
                        readouts
                        comparison
                    } else {
                        untrustworthy
                    }
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Rename climb", isPresented: $renaming) {
            TextField("Blue slab by the fan", text: $draftLabel)
            Button("Save") { store.rename(climb, to: draftLabel) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Climbs sharing a label are compared against each other.")
        }
        .task { aspect = await VideoInfo.aspect(of: climb.videoURL) }
        .onDisappear { playback.player.pause() }
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 7) {
                // Tappable, because a typo in the label quietly stops this climb
                // being grouped with its own other attempts.
                Button {
                    draftLabel = climb.label
                    renaming = true
                } label: {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(Theme.title(27))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                verdict

                Text(climb.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 10)
            if let onClose {
                Button("Done") { onClose() }
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    /// What this attempt came down to, on one line under the name. It is the
    /// same sentence the library card shows, so a climb reads the same wherever
    /// you meet it.
    @ViewBuilder
    private var verdict: some View {
        if let top = climb.findings.first {
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.ember[min(top.severity.rawValue, Theme.ember.count - 1)])
                    .frame(width: 7, height: 7)
                Text(top.severity.label)
                    .font(Theme.ui(13.5, .semibold))
                    .foregroundStyle(Theme.ink2)
                Text("·").foregroundStyle(Theme.ink3)
                Text(top.kind.title)
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
        } else if climb.metrics.isTrustworthy {
            Text("Nothing worth flagging")
                .font(Theme.ui(13.5))
                .foregroundStyle(Theme.ink2)
        }
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            PlayerLayerView(player: playback.player)
            OverlayView(
                frames: climb.frames,
                time: playback.time,
                videoAspect: aspect,
                metersPerUnit: BodyScale.metersPerUnit(frames: climb.frames, body: store.body),
                reachRadius: BodyScale.reachRadius(frames: climb.frames, body: store.body),
                title: label
            )
            // Top right, because the back ring now floats top left.
            VStack {
                HStack {
                    Spacer()
                    StatusChip(
                        text: "Tracking \(Int(climb.metrics.trackingConfidence * 100))%",
                        dot: climb.metrics.isTrustworthy ? Theme.ok : Theme.ember[1]
                    )
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 58)
        }
        // The video's own aspect, so it fills the width exactly and there is
        // never a letterbox. Cropping to a fixed height would be the other way
        // to kill the black bars, and it would cut the climber out of a tall
        // portrait clip, which is the one thing the screen exists to show.
        .aspectRatio(aspect > 0 ? aspect : 9.0 / 16.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        // The back control rides on the footage rather than being pinned to the
        // screen. Pinned, it ends up as a white-on-dark disc floating over white
        // paper as soon as you scroll past the video, which reads as a bug.
        .overlay(alignment: .topLeading) {
            BackOverlayButton { onClose?() ?? dismiss() }
                .padding(.leading, Theme.gutter - 6)
                .padding(.top, 52)
        }
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
    }

    // MARK: Telemetry
    //
    // The running commentary, under the stage rather than over it. On a portrait
    // clip a panel floating on the footage covers the climber it is describing.

    @ViewBuilder
    private var telemetry: some View {
        let phases = PhaseTimeline.build(frames: climb.frames)
        if let r = PhaseTimeline.readout(frames: climb.frames, phases: phases, at: playback.time) {
            TelemetryPanel(
                readout: r,
                com: nearestCOM(playback.time),
                previous: nearestCOM(playback.time - 0.5),
                metersPerUnit: BodyScale.metersPerUnit(frames: climb.frames, body: store.body),
                title: label
            )
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 14)

            Text("The numbers on the climber are joint angles in degrees: elbows, shoulders, hips and knees. 180° is a straight limb hanging off the skeleton. The lower the number, the more of that load a muscle is holding.")
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 10)
        }
    }

    private func nearestCOM(_ t: Double) -> CGPoint? {
        guard t >= 0 else { return nil }
        return climb.frames
            .filter { $0.com != nil }
            .min { abs($0.time - t) < abs($1.time - t) }?.com
    }

    private var scrubber: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line).frame(height: 2)
                    Rectangle().fill(Theme.accent)
                        .frame(width: progressWidth(geo.size.width), height: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        guard playback.duration > 0, geo.size.width > 0 else { return }
                        let ratio = min(max(g.location.x / geo.size.width, 0), 1)
                        playback.seek(to: ratio * playback.duration)
                    }
                )
            }
            .frame(height: 22)

            HStack(spacing: 14) {
                Text(timecode(playback.time))
                    .font(Theme.ui(12.5)).monospacedDigit()
                    .foregroundStyle(Theme.ink3)

                Spacer(minLength: 4)

                // One frame back, play, one frame forward. At a quarter speed a
                // deadpoint is still four or five frames, so the steps are what
                // actually let you sit on the moment rather than pass over it.
                Button { playback.step(-1) } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back one frame")

                Button { playback.toggle() } label: {
                    Text(playback.isPlaying ? "Pause" : "Play")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minWidth: 46, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { playback.step(1) } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forward one frame")

                Spacer(minLength: 4)

                Button { playback.cycleRate() } label: {
                    Text(speedLabel)
                        .font(Theme.ui(12.5, .semibold)).monospacedDigit()
                        .foregroundStyle(playback.rate == 1 ? Theme.ink3 : .white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(playback.rate == 1 ? Theme.surface2 : Theme.accent,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    /// "1x", "0.5x", "0.25x", with the duration no longer shown beside it.
    /// The timeline already says how long the clip is, and the speed is the
    /// control people will reach for here.
    private var speedLabel: String {
        let r = playback.rate
        if r == 1 { return "1x" }
        return r == 0.5 ? "0.5x" : "0.25x"
    }

    private func progressWidth(_ total: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return total * CGFloat(min(max(playback.time / playback.duration, 0), 1))
    }

    private func timecode(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    // MARK: One thing at a time

    /// How the attempt ended, and if it ended on the mat, what was already
    /// going wrong when it did.
    ///
    /// The cause is not a new judgement invented for the fall. It is whichever
    /// finding was still open in the seconds before it, because Trace has never
    /// seen the route and is not entitled to an opinion about the move itself.
    @ViewBuilder
    private var ending: some View {
        let outcome = OutcomeEngine.outcome(frames: climb.frames)
        switch outcome {
        case .topped(let at):
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("You topped it")
                Text("You reached your high point at \(timecode(at)) and held it. Trace has marked this a send. It works that out from where your body went, not from the route, so Mark unsent takes it back.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 20)
            .onTapGesture { playback.seek(to: max(0, at - 1)) }

        case .fell(let at, let rise):
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("You came off at \(timecode(at))")
                Text(fallSummary(rise: rise))
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                if let cause = OutcomeEngine.cause(of: outcome, findings: climb.findings) {
                    Hairline().padding(.vertical, 2)
                    Text("What was already going wrong")
                        .font(Theme.ui(12.5, .semibold))
                        .foregroundStyle(Theme.ink3)
                    Text("\(cause.kind.title.lowercased().prefix(1).uppercased() + cause.kind.title.lowercased().dropFirst()), from \(cause.timecode). \(cause.message)")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(cause.kind.drill)
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                } else {
                    Hairline().padding(.vertical, 2)
                    Text("Nothing Trace measures was going wrong in the seconds before it. That happens: a hold can simply be too small, or the move too long. Play the last two seconds back at a quarter speed and look at where your weight was.")
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    playback.seek(to: max(0, at - OutcomeEngine.lookBack))
                } label: {
                    Text("Play the two seconds before it")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 20)

        case .unclear:
            EmptyView()
        }
    }

    /// How far up it got, in the only unit available. Trace does not know the
    /// wall's height, so it cannot say how close to the top that was.
    private func fallSummary(rise: Double) -> String {
        let body = String(format: "%.1f", rise / 2.0)
        return "Your center of mass had climbed about \(body) body lengths by then. Trace has not seen the route, so it cannot tell you how close to the finish that was, only what your body was doing on the way."
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let top = climb.findings.first {
                SectionTitle("Work on this")
                FindingCard(finding: top)
                    .onTapGesture { playback.seek(to: top.start) }

                if climb.findings.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllFindings.toggle() }
                    } label: {
                        Text(showAllFindings
                             ? "Hide the rest"
                             : "\(climb.findings.count - 1) more, if you want them")
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showAllFindings {
                        VStack(spacing: 10) {
                            ForEach(climb.findings.dropFirst()) { f in
                                FindingCard(finding: f, showDrill: false)
                                    .onTapGesture { playback.seek(to: f.start) }
                            }
                        }
                    }
                }
            } else {
                SectionTitle("That was clean")
                Text("No leak crossed the threshold worth mentioning. Climb it again and see whether it gets smoother, or take it to something harder.")
                    .font(Theme.body(14.5))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
    }

    // MARK: Readouts

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Measurements")
            ReadoutGrid {
                Readout(label: "Entropy", value: String(format: "%.2f", climb.metrics.entropy),
                        unit: "nats", delta: entropyDelta)
                Readout(label: "Smoothness", value: String(format: "%.1f", climb.metrics.logJerk),
                        unit: "ldlj")
                // Zero means MetricsEngine declined: the climb ended near where
                // it started, so there is no straight line to compare against.
                // Printing "0.00" would read as a measurement rather than as a
                // refusal to make one.
                Readout(label: "Path ratio",
                        value: climb.metrics.pathRatio > 0
                            ? String(format: "%.2f", climb.metrics.pathRatio) : "—",
                        unit: climb.metrics.pathRatio > 0 ? "×" : "went nowhere net")
                Readout(label: "Static elbow",
                        value: "\(Int(climb.metrics.staticElbowAngle.rounded()))", unit: "°")
                Readout(label: "Stops", value: "\(climb.metrics.pauseCount)",
                        unit: climb.metrics.pauseTotal > 0
                              ? "\(Int(climb.metrics.pauseTotal.rounded()))s" : nil)
                Readout(label: "Foot resets", value: "\(climb.metrics.footAdjustments)")
                Readout(label: "Hips over feet",
                        value: String(format: "%.2f", climb.metrics.comOffsetFromFeet),
                        unit: "torso")
                // No dynamic moves is not the same as perfect timing, so it reads
                // as nothing measured rather than as a zero.
                Readout(label: "Deadpoint",
                        value: climb.metrics.hasDynamicMoves
                            ? "\(Int(climb.metrics.meanDeadpointError.rounded()))" : "—",
                        unit: climb.metrics.hasDynamicMoves ? "ms off" : "no dynos")
                if let lift {
                    // A ratio, so it needs no scale and no weight. 1.4 means you
                    // lifted yourself 40 percent further than the route asked.
                    Readout(label: "Lifting done",
                            value: String(format: "%.2f", lift.ratio),
                            unit: "×",
                            hint: liftHint(lift))
                }
                if let work {
                    Readout(label: "Work against gravity",
                            value: String(format: "%.1f", work.gross / 1000),
                            unit: "kJ",
                            // Only worth saying when some of it was spent twice.
                            hint: work.gross - work.net > 50
                                ? String(format: "%.1f kJ of it was the route itself",
                                         work.net / 1000)
                                : "None of it was spent twice")
                }
            }
            Text(measurementNote)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
    }

    /// The rise and fall of the center of mass. Computed here rather than stored,
    /// because it is a reading of a path the climb already carries.
    private var lift: BodyScale.Lift? {
        BodyScale.lift(path: climb.metrics.comPath)
    }

    private var work: (net: Double, gross: Double)? {
        guard let lift else { return nil }
        return BodyScale.work(joules: lift,
                              metersPerUnit: BodyScale.metersPerUnit(frames: climb.frames,
                                                                     body: store.body),
                              body: store.body)
    }

    private func liftHint(_ lift: BodyScale.Lift) -> String {
        lift.ratio < 1.15
            ? "Almost none of it repeated"
            : String(format: "%.0f percent of it repeated", (lift.ratio - 1) * 100)
    }

    private var measurementNote: String {
        let base = "Lower entropy and lower smoothness numbers mean less wasted movement. They compare against your own attempts, not against other climbers."
        if work != nil {
            return base + " The work figure counts gravity only, so it is a floor on what the climb cost rather than the cost itself."
        }
        if store.body.hasScale {
            return base + " Add your weight on the personal info screen and the lifting reads in joules as well."
        }
        return base
    }

    private var entropyDelta: String? {
        let prior = Store.shared.attempts(matching: climb.label)
            .filter { $0.id != climb.id && $0.metrics.isTrustworthy }
        guard let first = prior.first else { return nil }
        let d = climb.metrics.entropy - first.metrics.entropy
        guard abs(d) > 0.01 else { return nil }
        return String(format: "%@ %.2f vs attempt 1", d < 0 ? "↓" : "↑", abs(d))
    }

    // MARK: Your own betas, compared against each other
    //
    // Trace never suggests a sequence. It tells you which of yours cost the least.

    @ViewBuilder
    private var comparison: some View {
        let attempts = Store.shared.attempts(matching: climb.label)
            .filter { $0.metrics.isTrustworthy }
        // Lettered in the order you first tried them, so Sequence A is the way you
        // went at it first. Cheapest is marked separately rather than implied by rank.
        let clusters = BetaClustering.cluster(attempts).sorted {
            ($0.climbs.first?.recordedAt ?? .distantPast)
                < ($1.climbs.first?.recordedAt ?? .distantPast)
        }
        let cheapest = attempts.min { $0.metrics.entropy < $1.metrics.entropy }

        if attempts.count > 1 {
            VStack(alignment: .leading, spacing: 16) {
                Hairline()
                SectionTitle(clusters.count > 1
                             ? "You solved it more than one way"
                             : "Same way each time")
                    .padding(.top, 8)

                if let summary = BetaClustering.summary(for: clusters,
                                                        attemptCount: attempts.count) {
                    Text(summary)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(clusters.enumerated()), id: \.element.id) { index, cluster in
                    VStack(alignment: .leading, spacing: 8) {
                        if clusters.count > 1 {
                            HStack {
                                MicroLabel(
                                    text: "Sequence \(letter(index))",
                                    color: cluster.climbs.contains(where: { $0.id == cheapest?.id })
                                        ? Theme.accentText : Theme.ink3
                                )
                                Spacer()
                                if cluster.climbs.contains(where: { $0.id == cheapest?.id }) {
                                    MicroLabel(text: "Cheapest", color: Theme.accentText)
                                }
                            }
                        }

                        VStack(spacing: 1) {
                            ForEach(cluster.climbs) { attempt in
                                attemptRow(
                                    attempt,
                                    index: (attempts.firstIndex { $0.id == attempt.id } ?? 0) + 1,
                                    maxEntropy: attempts.map(\.metrics.entropy).max() ?? 1,
                                    isCheapest: attempt.id == cheapest?.id
                                )
                            }
                        }
                        .background(Theme.line)
                        .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
                    }
                }

                Text("Grouped by the shape of your center-of-mass path, not by the holds. Trace never sees the wall.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 156)
        } else {
            Color.clear.frame(height: 156)
        }
    }

    private func letter(_ i: Int) -> String {
        String(UnicodeScalar(65 + min(i, 25))!)
    }

    private func attemptRow(_ attempt: Climb, index: Int,
                            maxEntropy: Double, isCheapest: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(Theme.ui(12.5)).monospacedDigit()
                .foregroundStyle(Theme.ink3)
                .frame(width: 18, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.surface2).frame(height: 8)
                    Rectangle()
                        .fill(isCheapest ? Theme.accent : Theme.ink3)
                        .frame(width: maxEntropy > 0
                               ? geo.size.width * CGFloat(attempt.metrics.entropy / maxEntropy)
                               : 0,
                               height: 8)
                }
                .frame(height: geo.size.height, alignment: .center)
            }
            .frame(height: 18)

            Text(String(format: "%.2f", attempt.metrics.entropy))
                .font(Theme.ui(12.5, .medium)).monospacedDigit()
                .foregroundStyle(isCheapest ? Theme.accentText : Theme.ink2)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(attempt.id == climb.id ? Theme.surface2 : Theme.surface)
    }

    // MARK: Low tracking

    private var untrustworthy: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("I could not see that one clearly")
            Text("Only \(Int(climb.metrics.trackingConfidence * 100)) percent of frames had a usable skeleton, so any coaching from this clip would be guesswork. Confidently wrong feedback is worse than none.")
                .font(Theme.body(14.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: "Usually one of these")
                Text("The phone was too far away, you were facing into the wall for most of the climb, or another climber crossed the frame.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 156)
    }
}
