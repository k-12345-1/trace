import SwiftUI
import AVFoundation

// MARK: - Playback

@MainActor
final class PlaybackModel: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false

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
            player.play()
        }
        isPlaying.toggle()
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
                    header
                    stage
                    scrubber
                    Hairline()
                    if climb.metrics.isTrustworthy {
                        headline
                        Hairline()
                        readouts
                        comparison
                    } else {
                        untrustworthy
                    }
                }
            }
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
            VStack(alignment: .leading, spacing: 5) {
                // Tappable, because a typo in the label quietly stops this climb
                // being grouped with its own other attempts.
                Button {
                    draftLabel = climb.label
                    renaming = true
                } label: {
                    HStack(spacing: 7) {
                        Text(label)
                            .font(Theme.heading(19))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
                MicroLabel(text: climb.recordedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Spacer()
            if let onClose {
                Button("DONE") { onClose() }
                    .font(Theme.mono(11, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            PlayerLayerView(player: playback.player)
            OverlayView(
                frames: climb.frames,
                time: playback.time,
                videoAspect: aspect
            )
            VStack {
                HStack {
                    StatusChip(
                        text: "Tracking \(Int(climb.metrics.trackingConfidence * 100))%",
                        dot: climb.metrics.isTrustworthy ? Theme.ok : Theme.ember[1]
                    )
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(height: 400)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
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

            HStack {
                Text(timecode(playback.time))
                    .font(Theme.mono(10.5)).monospacedDigit()
                    .foregroundStyle(Theme.ink3)
                Spacer()
                Button(playback.isPlaying ? "PAUSE" : "PLAY") { playback.toggle() }
                    .font(Theme.mono(10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Text(timecode(playback.duration))
                    .font(Theme.mono(10.5)).monospacedDigit()
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
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

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let top = climb.findings.first {
                SectionHeader(micro: "The one thing", title: "Work on this")
                FindingCard(finding: top)
                    .onTapGesture { playback.seek(to: top.start) }

                if climb.findings.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllFindings.toggle() }
                    } label: {
                        Text((showAllFindings ? "Hide the rest" : "\(climb.findings.count - 1) more, if you want them").uppercased())
                            .font(Theme.mono(10.5, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(Theme.ink3)
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
                SectionHeader(micro: "Nothing to flag", title: "That was clean")
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
            MicroLabel(text: "Measurements")
            ReadoutGrid {
                Readout(label: "Entropy", value: String(format: "%.2f", climb.metrics.entropy),
                        unit: "nats", delta: entropyDelta)
                Readout(label: "Smoothness", value: String(format: "%.1f", climb.metrics.logJerk),
                        unit: "ldlj")
                Readout(label: "Path ratio", value: String(format: "%.2f", climb.metrics.pathRatio),
                        unit: "×")
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
            }
            Text("Lower entropy and lower smoothness numbers mean less wasted movement. They compare against your own attempts, not against other climbers.")
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
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
                SectionHeader(
                    micro: clusters.count > 1 ? "\(clusters.count) sequences" : "Your attempts",
                    title: clusters.count > 1
                        ? "You solved it more than one way"
                        : "Same way each time"
                )
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

                Text("Grouped by the shape of your centre-of-mass path, not by the holds. Trace never sees the wall.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        } else {
            Color.clear.frame(height: 40)
        }
    }

    private func letter(_ i: Int) -> String {
        String(UnicodeScalar(65 + min(i, 25))!)
    }

    private func attemptRow(_ attempt: Climb, index: Int,
                            maxEntropy: Double, isCheapest: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(Theme.mono(11))
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
                .font(Theme.mono(11)).monospacedDigit()
                .foregroundStyle(isCheapest ? Theme.accentText : Theme.ink2)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(attempt.id == climb.id ? Theme.surface2 : Theme.surface)
    }

    // MARK: Low tracking

    private var untrustworthy: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(micro: "Low tracking", title: "I could not see that one clearly")
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
        .padding(.vertical, 24)
    }
}
