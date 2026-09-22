import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generates demo climbs for the simulator: a synthetic wall, a synthetic climber,
// and then the REAL analysis pipeline run over the same joint positions used to
// draw them. Only the climber's motion is invented. Every number in the seeded
// data comes out of MetricsEngine and FindingEngine exactly as it would from a
// real clip.
//
// Usage: seeddemo <app Documents directory>

let W = 540, H = 960, FPS = 30

// MARK: - The synthetic climber

enum Style {
    case tidy       // straight arms, hips in, continuous
    case leaky      // bent arms, hips hanging out, stop-start
    case wandering  // the same climb solved by traversing around
    case improving  // the leak half fixed, which is what progress looks like
}

/// How a given climber moves. The differences here are what the analysis picks up.
struct StyleParams {
    var sway: Double        // lateral wander amplitude
    var cycles: Double      // how many times they drift across going up
    var bend: Double        // elbow bend, 0 is a dead straight arm
    var feetOffset: Double  // how far the hips hang off from over the feet
    var stutter: Bool       // stop-start rather than continuous
    var excursion: Double   // one big detour partway up
}

func params(_ style: Style) -> StyleParams {
    switch style {
    case .tidy:
        return StyleParams(sway: 0.020, cycles: 2.0, bend: 0.05,
                           feetOffset: 0.012, stutter: false, excursion: 0)
    case .leaky:
        return StyleParams(sway: 0.105, cycles: 4.0, bend: 0.34,
                           feetOffset: 0.085, stutter: true, excursion: 0)
    case .wandering:
        return StyleParams(sway: 0.120, cycles: 3.0, bend: 0.30,
                           feetOffset: 0.045, stutter: false, excursion: 0.20)
    case .improving:
        return StyleParams(sway: 0.070, cycles: 3.0, bend: 0.24,
                           feetOffset: 0.040, stutter: false, excursion: 0)
    }
}

/// Elbow placed off the line from shoulder to hand. bend = 0 gives a straight arm;
/// the angle at the elbow works out as 180 - 2·atan(2·bend) degrees.
func elbow(shoulder: (Double, Double), hand: (Double, Double),
           bend: Double, outward: Double) -> Joint {
    let dx = hand.0 - shoulder.0, dy = hand.1 - shoulder.1
    let d = (dx * dx + dy * dy).squareRoot()
    guard d > 1e-6 else { return Joint(x: shoulder.0, y: shoulder.1, confidence: 0.93) }
    let mx = (shoulder.0 + hand.0) / 2, my = (shoulder.1 + hand.1) / 2
    let px = -dy / d, py = dx / d
    return Joint(x: mx + px * bend * d * outward,
                 y: my + py * bend * d * outward, confidence: 0.93)
}

/// Joint positions in normalised image space, origin top-left.
func pose(t: Double, progress p: Double, style: Style) -> [JointID: Joint] {
    let s = params(style)

    // Stop-start climbers hold still between moves, which shows up as flat
    // stretches in the centre-of-mass path and as pauses in the metrics.
    let eased: Double
    if s.stutter {
        let steps = 7.0
        let whole = (p * steps).rounded(.down)
        let frac = p * steps - whole
        eased = (whole + max(0, min(1, (frac - 0.5) / 0.5))) / steps
    } else {
        eased = p
    }

    var sway = s.sway * sin(eased * s.cycles * .pi)
    // A detour partway up: the same boulder solved by going around.
    sway += s.excursion * exp(-pow((eased - 0.5) / 0.14, 2))

    let hipY = 0.80 - eased * 0.58
    let hipX = 0.50 + sway
    let torso = 0.115
    let shoulderY = hipY - torso

    let cycle = eased * 2.5 * .pi
    let reachL = sin(cycle), reachR = sin(cycle + .pi)

    func j(_ x: Double, _ y: Double) -> Joint { Joint(x: x, y: y, confidence: 0.93) }

    let shoulderL = (hipX - 0.042, shoulderY)
    let shoulderR = (hipX + 0.042, shoulderY)
    let handL = (hipX - 0.058, shoulderY - 0.110 - 0.020 * max(0, reachL))
    let handR = (hipX + 0.058, shoulderY - 0.110 - 0.020 * max(0, reachR))

    return [
        .nose:          j(hipX, shoulderY - 0.052),
        .neck:          j(hipX, shoulderY - 0.018),
        .leftShoulder:  j(shoulderL.0, shoulderL.1),
        .rightShoulder: j(shoulderR.0, shoulderR.1),
        .leftElbow:     elbow(shoulder: shoulderL, hand: handL, bend: s.bend, outward: -1),
        .rightElbow:    elbow(shoulder: shoulderR, hand: handR, bend: s.bend, outward: 1),
        .leftWrist:     j(handL.0, handL.1),
        .rightWrist:    j(handR.0, handR.1),
        .leftHip:       j(hipX - 0.032, hipY),
        .rightHip:      j(hipX + 0.032, hipY),
        .leftKnee:      j(hipX - 0.050 - s.feetOffset * 0.5, hipY + 0.085),
        .rightKnee:     j(hipX + 0.050 - s.feetOffset * 0.5, hipY + 0.085),
        .leftAnkle:     j(hipX - 0.040 - s.feetOffset, hipY + 0.165 + 0.016 * reachR),
        .rightAnkle:    j(hipX + 0.040 - s.feetOffset, hipY + 0.165 + 0.016 * reachL)
    ]
}

// MARK: - Drawing

let holdColours: [(Double, Double, Double)] = [
    (0.71, 0.28, 0.24), (0.24, 0.42, 0.71), (0.79, 0.64, 0.15),
    (0.29, 0.55, 0.35), (0.48, 0.31, 0.64)
]

struct Hold { var x: Double; var y: Double; var rx: Double; var ry: Double; var a: Double; var c: Int }

func makeHolds(seed: UInt64) -> [Hold] {
    var rng = SeededRNG(seed: seed)
    return (0..<26).map { _ in
        Hold(x: rng.next(0.06, 0.94), y: rng.next(0.03, 0.97),
             rx: rng.next(0.018, 0.034), ry: rng.next(0.012, 0.022),
             a: rng.next(-0.7, 0.7), c: Int(rng.next(0, 4.99)))
    }
}

struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let v = Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        return lo + v * (hi - lo)
    }
}

func drawFrame(ctx: CGContext, joints: [JointID: Joint], holds: [Hold]) {
    let w = Double(W), h = Double(H)

    // Wall
    ctx.setFillColor(CGColor(red: 0.078, green: 0.063, blue: 0.055, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Panel seams
    ctx.setStrokeColor(CGColor(red: 0.13, green: 0.108, blue: 0.094, alpha: 1))
    ctx.setLineWidth(2)
    for x in stride(from: 0.25, through: 0.75, by: 0.25) {
        ctx.move(to: CGPoint(x: x * w, y: 0)); ctx.addLine(to: CGPoint(x: x * w, y: h))
    }
    for y in stride(from: 0.25, through: 0.75, by: 0.25) {
        ctx.move(to: CGPoint(x: 0, y: y * h)); ctx.addLine(to: CGPoint(x: w, y: y * h))
    }
    ctx.strokePath()

    // Holds, in every colour a gym actually uses.
    for hold in holds {
        let c = holdColours[hold.c]
        ctx.saveGState()
        ctx.translateBy(x: hold.x * w, y: hold.y * h)
        ctx.rotate(by: hold.a)
        ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.92))
        ctx.fillEllipse(in: CGRect(x: -hold.rx * w, y: -hold.ry * w,
                                   width: hold.rx * 2 * w, height: hold.ry * 2 * w))
        ctx.restoreGState()
    }

    // The climber. Drawn as a solid body so the app's chalk overlay reads on top.
    func p(_ id: JointID) -> CGPoint? {
        guard let j = joints[id] else { return nil }
        // Video origin is bottom-left, joints are top-left.
        return CGPoint(x: j.x * w, y: (1 - j.y) * h)
    }
    let bones: [(JointID, JointID)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(red: 0.34, green: 0.36, blue: 0.40, alpha: 1))
    ctx.setLineWidth(26)
    for (a, b) in bones {
        guard let p1 = p(a), let p2 = p(b) else { continue }
        ctx.move(to: p1); ctx.addLine(to: p2)
    }
    ctx.strokePath()

    if let nose = p(.nose) {
        ctx.setFillColor(CGColor(red: 0.34, green: 0.36, blue: 0.40, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: nose.x - 21, y: nose.y - 21, width: 42, height: 42))
    }
}

// MARK: - Video writing

func writeClip(to url: URL, frames: [[JointID: Joint]], holds: [Hold]) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: W, AVVideoHeightKey: H
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: W,
            kCVPixelBufferHeightKey as String: H
        ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let space = CGColorSpaceCreateDeviceRGB()
    for (i, joints) in frames.enumerated() {
        guard let pool = adaptor.pixelBufferPool else { break }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { break }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                               width: W, height: H, bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: space,
                               bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            drawFrame(ctx: ctx, joints: joints, holds: holds)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        while !input.isReadyForMoreMediaData { usleep(2000) }
        adaptor.append(buffer, withPresentationTime:
            CMTime(value: CMTimeValue(i), timescale: CMTimeScale(FPS)))
    }

    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if writer.status == .failed { throw writer.error ?? URLError(.unknown) }
}

// MARK: - Build one demo climb through the real pipeline

func makeClimb(label: String, style: Style, seconds: Double, daysAgo: Double,
               seed: UInt64, videosDir: URL, degradeTracking: Bool = false) throws -> Climb {
    let count = Int(seconds * Double(FPS))
    let holds = makeHolds(seed: seed)

    var drawn: [[JointID: Joint]] = []
    var poseFrames: [PoseFrame] = []
    var jitter = SeededRNG(seed: seed &+ 977)

    for i in 0..<count {
        let t = Double(i) / Double(FPS)
        let joints = pose(t: t, progress: Double(i) / Double(count - 1), style: style)
        drawn.append(joints)

        // One clip is deliberately half-untrackable, so the demo shows what the
        // app does when it could not see clearly.
        let lost = degradeTracking && (i % 10 < 6)
        if lost {
            poseFrames.append(PoseFrame(time: t, joints: [:], com: nil, meanConfidence: 0))
        } else {
            // Vision jitters a few pixels frame to frame. Reproduce that, or the
            // demo numbers would be cleaner than any real clip.
            var noisy: [JointID: Joint] = [:]
            for (id, j) in joints {
                noisy[id] = Joint(x: j.x + jitter.next(-0.002, 0.002),
                                  y: j.y + jitter.next(-0.002, 0.002),
                                  confidence: j.confidence)
            }
            poseFrames.append(PoseFrame(time: t, joints: noisy,
                                        com: CenterOfMass.estimate(joints: noisy),
                                        meanConfidence: 0.93))
        }
    }

    // The same smoothing pass PoseTracker applies to a real clip.
    poseFrames = PoseTracker.smooth(poseFrames)

    let filename = "\(UUID().uuidString).mov"
    try writeClip(to: videosDir.appendingPathComponent(filename), frames: drawn, holds: holds)

    // The real engines, not hand-written numbers.
    let metrics = MetricsEngine.compute(frames: poseFrames)
    let findings = FindingEngine.findings(from: metrics, frames: poseFrames)

    return Climb(recordedAt: Date().addingTimeInterval(-daysAgo * 86400),
                 videoFilename: filename, label: label,
                 metrics: metrics, findings: findings, frames: poseFrames)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: seeddemo <Documents dir>\n".utf8))
    exit(2)
}
let documents = URL(fileURLWithPath: args[1])
let videos = documents.appendingPathComponent("Clips", isDirectory: true)
try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)

var climbs: [Climb] = []

// Three attempts on one boulder: twice the same way, once solved differently.
climbs.append(try makeClimb(label: "Blue slab by the fan", style: .leaky,
                            seconds: 11, daysAgo: 16, seed: 11, videosDir: videos))
climbs.append(try makeClimb(label: "Blue slab by the fan", style: .leaky,
                            seconds: 10, daysAgo: 16, seed: 12, videosDir: videos))
climbs.append(try makeClimb(label: "Blue slab by the fan", style: .wandering,
                            seconds: 12, daysAgo: 15, seed: 13, videosDir: videos))

// Repeats on one problem, starting to tidy up.
climbs.append(try makeClimb(label: "Red overhang", style: .leaky,
                            seconds: 12, daysAgo: 11, seed: 21, videosDir: videos))
climbs.append(try makeClimb(label: "Red overhang", style: .improving,
                            seconds: 10, daysAgo: 10, seed: 22, videosDir: videos))

// One clip the app could not see properly.
climbs.append(try makeClimb(label: "Yellow arete", style: .improving, seconds: 9,
                            daysAgo: 7, seed: 31, videosDir: videos,
                            degradeTracking: true))

climbs.append(try makeClimb(label: "Yellow arete", style: .improving,
                            seconds: 9, daysAgo: 6, seed: 32, videosDir: videos))
climbs.append(try makeClimb(label: "Green traverse", style: .improving,
                            seconds: 8, daysAgo: 2, seed: 41, videosDir: videos))
climbs.append(try makeClimb(label: "Green traverse", style: .improving,
                            seconds: 8, daysAgo: 1, seed: 42, videosDir: videos))

climbs.sort { $0.recordedAt > $1.recordedAt }

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
try encoder.encode(climbs).write(to: documents.appendingPathComponent("climbs.json"))

// A focus started a fortnight ago. The baseline is genuinely the mean of the
// earliest tracked climbs, so the progress the app shows is a real measurement.
let oldest = climbs.filter { $0.metrics.isTrustworthy }
    .sorted { $0.recordedAt < $1.recordedAt }.prefix(3)
if !oldest.isEmpty {
    let baseline = oldest.map { FocusEngine.value(for: .bentArms, in: $0.metrics) }
        .reduce(0, +) / Double(oldest.count)
    let focus = Focus(kind: .bentArms,
                      startedAt: Date().addingTimeInterval(-16 * 86400),
                      baseline: baseline, latest: baseline)
    try encoder.encode(focus).write(to: documents.appendingPathComponent("focus.json"))
    print(String(format: "Focus: bent arms, baseline %.0f°, target %.0f°",
                 baseline, FocusEngine.target(for: .bentArms, baseline: baseline)))
}

print("Seeded \(climbs.count) demo climbs with real clips.")
for c in climbs.sorted(by: { $0.recordedAt < $1.recordedAt }) {
    let m = c.metrics
    print(String(format: "  %-22@  H %.2f  jerk %5.1f  elbow %3d°  hips %.2f  track %3d%%  %@",
                 c.label as NSString, m.entropy, m.logJerk,
                 Int(m.staticElbowAngle.rounded()), m.comOffsetFromFeet,
                 Int(m.trackingConfidence * 100),
                 (c.findings.first?.kind.rawValue ?? "no findings") as NSString))
}
