import SwiftUI
import AVFoundation
import UIKit

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

    /// Back or forward by a second, which on a boulder is two or three moves.
    ///
    /// Five seconds, the usual step, is most of a clip this short. A second is
    /// the difference between one move and the next, and the frame steps below
    /// are what get you inside a single one.
    static let skip = 1.0

    func skip(_ seconds: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(time + seconds, 0), duration))
    }

    var isMuted: Bool { player.isMuted }

    func mute(_ on: Bool) { player.isMuted = on }

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
        // Fill, not fit. Fit left a strip of paper either side of every
        // portrait clip once the height was capped; the wall now reaches the
        // edges of the phone and a little of the top and bottom is cropped,
        // which on a clip framed for a climber is floor and ceiling.
        v.playerLayer.videoGravity = .resizeAspectFill
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
    /// Kept across clips and across launches, because it is a preference about
    /// watching climbing videos, not about this one.
    @AppStorage("clipsMuted") private var clipsMuted = false
    @Environment(\.dismiss) private var dismiss
    @State private var aspect: Double = 9.0 / 16.0
    @State private var renaming = false
    @State private var draftLabel = ""
    /// Where the bottom of the footage currently sits on the screen.
    ///
    /// The clip is the header and runs to the very top, so this screen cannot
    /// take the paper band the rest of the app wears: it would be the picture
    /// cropped. But the clip scrolls away, and once it has, the paragraphs
    /// underneath pass beneath the clock exactly as they did everywhere else.
    /// So the cover is not always on, it arrives as the footage leaves.
    @State private var stageBottom: CGFloat = .greatestFiniteMagnitude

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
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The footage is the header. It runs to both edges and to
                    // the very top of the screen, under the status bar, with the
                    // back control floating on it.
                    stage
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: StageBottomKey.self,
                                                       value: geo.frame(in: .global).maxY)
                            }
                        }
                    // The scrubber belongs to the video, so it sits against it.
                    // It was two sections down, under the name and the live
                    // readout, which put the control for the clip below a
                    // paragraph about the clip. The telemetry follows, because
                    // what it shows is whatever the scrubber is pointing at.
                    scrubber
                    telemetry
                    header
                    // Above the measurements, and outside the check on them.
                    // A clip Trace could not track is exactly the climb whose
                    // only record is what the climber says about it.
                    NotesCard(climb: climb)
                    ClimbStyleCard(climb: climb)
                    if ResultsReadout.of(climb) == .cameraMoved {
                        cameraMoved
                    } else if ResultsReadout.of(climb) == .measurements {
                        efficiency
                        ending
                        wasted
                        headline
                        wentWell
                        reaches
                        Hairline()
                        readouts
                        comparison
                    } else {
                        untrustworthy
                    }
                }
                .holdsThePageWidth()
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(StageBottomKey.self) { stageBottom = $0 }
            // Arrives over the last twenty points of the footage leaving, so
            // there is no frame where it snaps on. A fade on the page itself
            // rather than paper painted over it, for the reason in
            // FadesUnderTheTop.
            .fadesUnderTheTop(coverOpacity)
        }
        .reachesTheTop()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Rename climb", isPresented: $renaming) {
            TextField("Blue slab by the fan", text: $draftLabel)
            Button("Save") { store.rename(climb, to: draftLabel) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Climbs sharing a label are compared against each other.")
        }
        .task {
            playback.mute(clipsMuted)
            aspect = await VideoInfo.aspect(of: climb.videoURL)
        }
        .onDisappear { playback.player.pause() }
        .preferredColorScheme(.light)
    }

    /// One where the footage has gone, zero while any of it is still showing.
    private var coverOpacity: Double {
        let fadeOver: CGFloat = 20
        let gone = 62 + fadeOver - stageBottom
        return Double(min(max(gone / fadeOver, 0), 1))
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
                    // Set in the title, not parked beside it: interpolated into
                    // the Text it sits on the title's own baseline and wraps
                    // with the last word.
                    (Text(label).font(Theme.title(27)).foregroundColor(Theme.ink)
                     + Text("  ")
                     + Text(Image(systemName: "pencil"))
                        .font(.system(size: 13)).foregroundColor(Theme.ink3))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
        .padding(.bottom, 20)
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

    /// How much of the screen the clip may take before the controls under it
    /// would be pushed off. Two thirds leaves the scrubber and the live readout
    /// visible on the shortest phone Trace supports.
    static let tallestStage: CGFloat = UIScreen.main.bounds.height * 0.66

    private var stage: some View {
        ZStack {
            PlayerLayerView(player: playback.player)
            OverlayView(
                frames: climb.frames,
                time: playback.time,
                videoAspect: aspect,
                fills: true,
                metersPerUnit: BodyScale.metersPerUnit(frames: climb.frames, body: store.body),
                reachRadius: BodyScale.reachRadius(frames: climb.frames, body: store.body),
                title: label
            )
        }
        // The video's own aspect, so it fills the width exactly and there is
        // never a letterbox. Cropping to a fixed height would be the other way
        // to kill the black bars, and it would cut the climber out of a tall
        // portrait clip, which is the one thing the screen exists to show.
        .aspectRatio(aspect > 0 ? aspect : 9.0 / 16.0, contentMode: .fill)
        // But not taller than this, whatever the clip's shape.
        //
        // A portrait clip filmed on a phone is taller than the phone it is
        // played back on, so honouring its aspect alone pushed the scrubber off
        // the bottom of the screen: the controls for the video were below the
        // fold on exactly the clips people actually film. Capped, a tall clip
        // loses a little width at the sides and keeps its player on screen.
        .frame(maxWidth: .infinity, maxHeight: Self.tallestStage)
        .clipped()
        // The back control rides on the footage rather than being pinned to the
        // screen. Pinned, it ends up as a white-on-dark disc floating over white
        // paper as soon as you scroll past the video, which reads as a bug.
        .overlay(alignment: .topLeading) {
            BackOverlayButton { onClose?() ?? dismiss() }
                .padding(.leading, Theme.gutter - 6)
                .padding(.top, 52)
        }
        // On the framed view, not inside the footage: the footage now fills
        // and crops, and anything laid inside it near the top is cropped with
        // it. The chip sat half under the status bar until it moved out here
        // beside the back ring.
        .overlay(alignment: .topTrailing) {
            StatusChip(
                text: "Tracking \(Int(climb.metrics.trackingConfidence * 100))%",
                dot: climb.metrics.isTrustworthy ? Theme.ok : Theme.ember[1]
            )
            .padding(.trailing, 14)
            .padding(.top, 58)
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

            // Everything the clip needs, on one line: where you are and how
            // long it runs, back and forward a second, back and forward a
            // frame, play, speed, sound.
            HStack(spacing: 6) {
                Text("\(timecode(playback.time)) / \(timecode(playback.duration))")
                    .font(Theme.ui(12)).monospacedDigit()
                    .foregroundStyle(Theme.ink3)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                control("gobackward", "Back a second") {
                    playback.skip(-PlaybackModel.skip)
                }
                // At a quarter speed a deadpoint is still four or five frames,
                // so the frame steps are what let you sit on the moment rather
                // than pass over it.
                control("backward.frame.fill", "Back one frame", size: 13) {
                    playback.step(-1)
                }

                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.blue, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                control("forward.frame.fill", "Forward one frame", size: 13) {
                    playback.step(1)
                }
                control("goforward", "Forward a second") {
                    playback.skip(PlaybackModel.skip)
                }

                Spacer(minLength: 2)

                Button { playback.cycleRate() } label: {
                    Text(speedLabel)
                        .font(Theme.ui(12, .semibold)).monospacedDigit()
                        .foregroundStyle(playback.rate == 1 ? Theme.ink3 : .white)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(playback.rate == 1 ? Theme.surface2 : Theme.accent,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed")

                // Sound off, and it stays off for every clip afterwards. A gym
                // is loud and most of what is on these clips is other people.
                control(clipsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        clipsMuted ? "Sound on" : "Sound off",
                        size: 13,
                        tint: clipsMuted ? Theme.accentText : Theme.ink3) {
                    clipsMuted.toggle()
                    playback.mute(clipsMuted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func control(_ symbol: String, _ label: String, size: CGFloat = 15,
                         tint: Color = Theme.ink2,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

    /// The grade, at the top, because it is the one thing a climber will look
    /// for first and the rest of the page is why it came out that way.
    @ViewBuilder
    private var efficiency: some View {
        if let reading = EfficiencyCache.read(climb) {
            EfficiencyCard(reading: reading)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
        }
    }

    /// The movement that went nowhere, with the moments it happened.
    ///
    /// Entropy already says how much of the climb was wasted. This says when,
    /// which is the difference between a number and something you can work on.
    @ViewBuilder
    private var wasted: some View {
        if let reading = WasteEngine.read(frames: MetricsEngine.ascent(climb.frames)),
           let summary = WasteEngine.summary(reading) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Movement that went nowhere")
                Text(summary)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                // Tappable, because the point of finding the moment is to look
                // at it.
                FlowOfChips(reading.excursions.prefix(6).map { e in
                    (timecode(e.start), { playback.seek(to: max(0, e.start - 0.3)) })
                })

                Text(WasteEngine.caveat)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 20)
        }
    }

    // MARK: Each reach

    /// Which moves the body made, and which the arm made on its own.
    ///
    /// The two ends of the climber's own range, rather than a score. "Keep your
    /// hips close to the wall" is true of climbing and useless on a move; this
    /// says which second of this climb to look at and what was different about
    /// it, and then the climber watches both and sees it.
    ///
    /// Only shown when the two ends are actually far apart. A climb where every
    /// reach was made the same way has nothing to compare, and picking a best
    /// and a worst out of nine numbers a few points apart is picking noise.
    @ViewBuilder
    private var reaches: some View {
        if let reading = ReachEngine.read(frames: MetricsEngine.ascent(climb.frames)),
           let body = reading.bodyLed, let arm = reading.armLed,
           reading.spread >= ReachEngine.worthShowing {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("How you made each reach")

                Text("A reach covers the gap between two holds two ways: your body travelling, and your arm extending. Across \(reading.reaches.count) reaches on this climb your body did \(percent(reading.medianShare)) of the work in the middle one, and these two were the extremes.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                reachRow(arm, title: "Your arm did this one",
                         detail: "\(arm.handTitle), \(torsoLengths(arm.travelled)) to the next hold and your shoulder followed \(torsoLengths(arm.carried)) of it.")
                reachRow(body, title: "Your body did this one",
                         detail: "\(body.handTitle), \(torsoLengths(body.travelled)) to the next hold and your shoulder came \(torsoLengths(body.carried)) with it.")

                if let armHips = arm.hipOpenness, let bodyHips = body.hipOpenness,
                   abs(armHips - bodyHips) >= ReachEngine.hipDifferenceWorthNaming {
                    Text(bodyHips < armHips
                         ? "Your hips were turned in for that second one and square to the wall for the first. Watch them back and see whether that is what did it."
                         : "Your hips were square for that second one and turned in for the first, which is the opposite of what a coach would predict. Worth watching.")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(ReachEngine.caveat)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 20)
        }
    }

    private func reachRow(_ reach: ReachEngine.Reach, title: String, detail: String) -> some View {
        Button { playback.seek(to: reach.lookAt) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(reach.timecode)
                    .font(Theme.ui(12, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accentWash, in: Capsule())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.serif(16, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(Theme.ui(13.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Torso lengths, said the way the rest of the app says them.
    private func torsoLengths(_ x: Double) -> String {
        String(format: "%.1f body lengths", x)
    }

    private func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

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

                let advice = FallAdvice.suggestions(frames: climb.frames, fellAt: at)
                if !advice.isEmpty {
                    Hairline().padding(.vertical, 2)
                    Text("What to try instead")
                        .font(Theme.ui(12.5, .semibold))
                        .foregroundStyle(Theme.ink3)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(advice) { s in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.move)
                                    .font(Theme.ui(14.5, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(s.because)
                                    .font(Theme.body(13.5))
                                    .foregroundStyle(Theme.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text(FallAdvice.caveat)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
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

    /// The other half of the climb.
    ///
    /// It sits after the correction rather than before it, because the thing
    /// you came for is the thing to fix, and it is silent when nothing cleared
    /// the bar: praise for turning up is worth what it costs.
    @ViewBuilder
    private var wentWell: some View {
        let strengths = StrengthEngine.strengths(from: climb.metrics, priorJerk: priorJerk)
        if !strengths.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("What went well")
                VStack(spacing: 10) {
                    ForEach(strengths) { s in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Theme.ok, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(s.kind.title)
                                        .font(Theme.serif(17, .semibold))
                                        .foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 6)
                                    Text(s.detail)
                                        .font(Theme.ui(12)).monospacedDigit()
                                        .foregroundStyle(Theme.ink3)
                                        .multilineTextAlignment(.trailing)
                                }
                                Text(s.kind.why)
                                    .font(Theme.ui(14))
                                    .foregroundStyle(Theme.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 26)
        }
    }

    /// This climber's own earlier smoothness, which is the only thing
    /// smoothness can honestly be compared against.
    private var priorJerk: [Double] {
        store.climbs
            .filter { $0.id != climb.id && $0.metrics.isTrustworthy }
            .compactMap { $0.metrics.movingJerk }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let top = climb.findings.first {
                SectionTitle("Work on this")
                FindingCard(finding: top, climb: climb)
                    .onTapGesture { playback.seek(to: top.start) }

                // All of them, worst first. They used to fold behind a link,
                // which hid the second and third things a climber wanted to
                // hear about behind a tap they did not know to make.
                if climb.findings.count > 1 {
                    SectionTitle("Also on this climb")
                        .padding(.top, 8)
                    VStack(spacing: 10) {
                        ForEach(climb.findings.dropFirst()) { f in
                            FindingCard(finding: f, climb: climb)
                                .onTapGesture { playback.seek(to: f.start) }
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

    @State private var moreOpen = false

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Measurements")
            ReadoutGrid {
                Readout(label: "Entropy", value: String(format: "%.2f", climb.metrics.entropy),
                        unit: "nats", delta: entropyDelta)
                // Per move, and a dash when there were too few moves to read.
                // The whole-climb number counted a rest as roughness.
                Readout(label: "Smoothness",
                        value: climb.metrics.movingJerk.map { String(format: "%.1f", $0) } ?? "—",
                        unit: climb.metrics.movingJerk == nil ? "too few moves" : "per move")
                // Zero means MetricsEngine declined: the climb ended near where
                // it started, so there is no straight line to compare against.
                // Printing "0.00" would read as a measurement rather than as a
                // refusal to make one.
                // Not the path ratio, which compared this against a straight
                // line up the wall that no boulder offers.
                Readout(label: "Between moves",
                        value: climb.metrics.moveWaste
                            .map { "\(Int(($0 * 100).rounded()))" } ?? "—",
                        unit: climb.metrics.moveWaste == nil ? "too few moves" : "% off the line",
                        hint: "travel not toward the next position")
                Readout(label: "Static elbow",
                        value: "\(Int(climb.metrics.staticElbowAngle.rounded()))", unit: "°")
                Readout(label: "Stops", value: "\(climb.metrics.pauseCount)",
                        unit: climb.metrics.pauseTotal > 0
                              ? "\(Int(climb.metrics.pauseTotal.rounded()))s" : nil)
                Readout(label: "Foot resets", value: "\(climb.metrics.footAdjustments)")
                // Hip widths, not torso lengths, and only while resting. Both
                // changed when the measure did and this label did not follow.
                Readout(label: "Weight outside feet",
                        value: climb.metrics.comOffsetFromFeet > 0
                            ? String(format: "%.2f", climb.metrics.comOffsetFromFeet) : "—",
                        unit: climb.metrics.comOffsetFromFeet > 0 ? "hip widths resting" : "no rests")
                // No dynamic moves is not the same as perfect timing, so it reads
                // as nothing measured rather than as a zero.
                Readout(label: "Deadpoint",
                        value: climb.metrics.hasDynamicMoves
                            ? "\(Int(climb.metrics.meanDeadpointError.rounded()))" : "—",
                        unit: climb.metrics.hasDynamicMoves ? "ms off" : "no dynos")
                // Friction is bought with normal force, and normal force comes
                // either from gravity or from a pair of contacts loaded toward
                // each other. These two say how much of the climb had a pair.
            }

            // The rest, folded away. Eleven numbers at once is a wall, and the
            // six above are the ones the findings and the grade are built from.
            // Nothing is removed: opposition, compression and the work done are
            // a tap away for anyone who came for them.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { moreOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(moreOpen ? "Fewer measurements" : "More measurements")
                        .font(Theme.ui(13.5, .semibold))
                    Image(systemName: moreOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if moreOpen {
                ReadoutGrid {
                Readout(label: "In opposition",
                        value: "\(Int((climb.metrics.bracketedFraction * 100).rounded()))",
                        unit: "% of the time")
                Readout(label: "Compression",
                        value: climb.metrics.compressionFraction > 0.01
                            ? "\(Int((climb.metrics.compressionFraction * 100).rounded()))" : "—",
                        unit: climb.metrics.compressionFraction > 0.01 ? "% squeezing" : "none")
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
        guard let torso = MetricsEngine.medianTorso(climb.frames) else { return nil }
        return BodyScale.lift(path: climb.metrics.comPath, torso: torso)
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

    /// One line, not a paragraph.
    ///
    /// This ran to three sentences of hedging under a grid of eleven numbers,
    /// which is the wordiest thing on the screen sitting under the densest.
    /// What a reader needs is the direction and who they are being compared
    /// against; the rest belongs to whoever goes looking.
    private var measurementNote: String {
        "Lower is smoother. Every number compares you against your own attempts."
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

                        // A card with hairlines between the rows, like every
                        // other list in the app. It was square-cornered
                        // rectangles inside a one pixel border, which is the
                        // only thing on the screen that looked drawn by
                        // somebody else.
                        VStack(spacing: 0) {
                            ForEach(Array(cluster.climbs.enumerated()), id: \.element.id) { row, attempt in
                                if row > 0 { Hairline().padding(.leading, 14) }
                                attemptRow(
                                    attempt,
                                    index: (attempts.firstIndex { $0.id == attempt.id } ?? 0) + 1,
                                    maxEntropy: attempts.map(\.metrics.entropy).max() ?? 1,
                                    isCheapest: attempt.id == cheapest?.id
                                )
                            }
                        }
                        .card()
                    }
                }

                Text("Grouped by the shape of your center-of-mass path, not by the holds. Trace never sees the wall.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomClearance)
        } else {
            Color.clear.frame(height: bottomClearance)
        }
    }

    /// Room under the last thing on the page.
    ///
    /// The floating tab bar needs about a hundred and fifty points of clearance,
    /// but only when there is a tab bar. This screen is pushed inside a tab when
    /// you open an attempt from its route, and presented as a cover straight
    /// after an analysis, and `onClose` is how it can tell: the cover supplies
    /// one, the push does not. Spending the clearance in the cover left a blank
    /// half screen under the measurements.
    private var bottomClearance: CGFloat { onClose == nil ? 156 : 44 }

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
                    Capsule().fill(Theme.surface2).frame(height: 8)
                    Capsule()
                        .fill(isCheapest ? Theme.accent : Theme.ink3.opacity(0.55))
                        .frame(width: maxEntropy > 0
                               ? max(8, geo.size.width * CGFloat(attempt.metrics.entropy / maxEntropy))
                               : 8,
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
        .padding(.vertical, 12)
        .background(attempt.id == climb.id ? Theme.accentWash : Color.clear)
    }

    // MARK: Low tracking

    /// The phone moved, so the measurements would be about the phone.
    ///
    /// A different failure from not being able to see the climb, and it has to
    /// read as one: Trace saw this one perfectly. What it cannot do is tell the
    /// climber's movement from the camera's, because both arrive as the same
    /// thing, a body shifting inside the frame.
    private var cameraMoved: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("The camera was moving")
            Text("Trace followed you the whole way, but the picture travelled \(cameraTravelText) while it did. Everything Trace measures about where you went is measured inside the frame, so when the frame moves too there is no telling your movement from the phone's, and the numbers would be about whoever was holding it.")
                .font(Theme.body(14.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: "Next time")
                Text("Stand the phone on the floor, square to the wall, with the whole boulder in frame, and leave it alone. A clip somebody filmed following you up the wall is worth watching back, and it is on the clip above, but it cannot be measured.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, bottomClearance)
    }

    /// Said as a multiple of the frame rather than in pixels, which mean
    /// nothing, or degrees, which Trace cannot know.
    private var cameraTravelText: String {
        guard let travel = climb.cameraTravel else { return "some way" }
        return travel < 1.5
            ? "about \(String(format: "%.1f", travel)) times the height of the picture"
            : "\(String(format: "%.0f", travel)) times the height of the picture"
    }

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
        .padding(.bottom, bottomClearance)
    }
}

/// Which of the three things the results screen has to say.
///
/// Named rather than left as a chain of `if`s in the view body, because the
/// order matters and the order is an argument. A clip filmed on a moving phone
/// is reported as that first, even when the tracking was also poor: "I could
/// not see you" is wrong when Trace saw the climb perfectly and simply cannot
/// tell the climber's movement from the camera's.
enum ResultsReadout: Equatable {
    /// The phone moved, so nothing measured from where the body went means
    /// anything about the body.
    case cameraMoved
    /// Too few frames had a usable skeleton.
    case unreadable
    /// Everything is measurable.
    case measurements

    static func of(_ climb: Climb) -> ResultsReadout {
        if climb.cameraWasStill == false { return .cameraMoved }
        if !climb.metrics.isTrustworthy { return .unreadable }
        return .measurements
    }
}


/// How far down the screen the footage still reaches.
private struct StageBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}
