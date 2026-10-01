import Foundation
import CoreGraphics

/// This climber's proportions, read off their own footage.
///
/// The figure that climbs a scanned route used to be the average body scaled
/// by height over span. This reads the body instead: how long the upper arm
/// is against the forearm, how wide the shoulders and hips are, how the thigh
/// compares with the shin, from the joints Vision tracked across every climb
/// the person has recorded.
///
/// A joint-to-joint distance in a photograph is the real length foreshortened
/// by whatever angle the limb made with the camera, so it is never longer than
/// the truth and is usually shorter. Across a few thousand frames of climbing
/// a limb will at some point lie nearly flat to the camera, so a high
/// percentile of its measured lengths is close to its real length. Not the
/// maximum: that is the frame where the tracker misplaced a joint.
///
/// Everything is a share of the arm span, measured the same way, so the
/// result drops straight into `BetaEngine.Shape`.
enum BodyMeasure {

    /// Which percentile of each segment's lengths stands for the real length.
    static let nearlyFlat = 0.92
    /// Frames before anything is said. A single clip is enough to read.
    static let minimumFrames = 60

    struct Lengths {
        var upperArm = 0.0, forearm = 0.0, shoulderWidth = 0.0, hipWidth = 0.0
        var torso = 0.0, thigh = 0.0, shin = 0.0, head = 0.0
        /// Wrist to wrist with both arms out, the span itself.
        var span: Double { 2 * (upperArm + forearm) + shoulderWidth }
    }

    static func lengths(in frames: [PoseFrame]) -> Lengths? {
        var upper: [Double] = [], fore: [Double] = [], shoulders: [Double] = [], hips: [Double] = []
        var torso: [Double] = [], thigh: [Double] = [], shin: [Double] = [], head: [Double] = []
        for f in frames {
            func d(_ a: JointID, _ b: JointID) -> Double? {
                guard let p = f.pt(a), let q = f.pt(b) else { return nil }
                return hypot(p.x - q.x, p.y - q.y)
            }
            for (a, b, c) in [(JointID.leftShoulder, JointID.leftElbow, JointID.leftWrist),
                              (.rightShoulder, .rightElbow, .rightWrist)] {
                if let u = d(a, b) { upper.append(u) }
                if let v = d(b, c) { fore.append(v) }
            }
            for (a, b, c) in [(JointID.leftHip, JointID.leftKnee, JointID.leftAnkle),
                              (.rightHip, .rightKnee, .rightAnkle)] {
                if let u = d(a, b) { thigh.append(u) }
                if let v = d(b, c) { shin.append(v) }
            }
            if let w = d(.leftShoulder, .rightShoulder) { shoulders.append(w) }
            if let w = d(.leftHip, .rightHip) { hips.append(w) }
            if let t = MetricsEngine.torsoLength(f) { torso.append(t) }
            if let ls = f.pt(.leftShoulder), let rs = f.pt(.rightShoulder), let n = f.pt(.nose) {
                let mid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
                head.append(hypot(n.x - mid.x, n.y - mid.y))
            }
        }
        guard upper.count >= minimumFrames, fore.count >= minimumFrames,
              shoulders.count >= minimumFrames, torso.count >= minimumFrames,
              thigh.count >= minimumFrames, shin.count >= minimumFrames else { return nil }
        var out = Lengths()
        out.upperArm = percentile(upper); out.forearm = percentile(fore)
        out.shoulderWidth = percentile(shoulders); out.torso = percentile(torso)
        out.thigh = percentile(thigh); out.shin = percentile(shin)
        out.hipWidth = hips.count >= minimumFrames ? percentile(hips) : out.shoulderWidth * 0.75
        out.head = head.count >= minimumFrames ? percentile(head) : out.torso * 0.5
        return out
    }

    static func percentile(_ xs: [Double], _ p: Double = nearlyFlat) -> Double {
        let s = xs.sorted()
        return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
    }

    /// The shape for the figure, or nil when there is not enough footage.
    ///
    /// Each share is kept within a range real bodies cover, so a tracker that
    /// put a knee on the far side of the mat for a frame or two cannot give
    /// the figure a leg to match. `fallback` supplies anything that could not
    /// be read.
    static func shape(from frames: [PoseFrame], fallback: BetaEngine.Shape = .average) -> BetaEngine.Shape? {
        guard let l = lengths(in: frames), l.span > 0.01 else { return nil }
        func share(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x / l.span, lo), hi) }
        var s = fallback
        s.upperArm = share(l.upperArm, 0.14, 0.24)
        s.forearm = share(l.forearm, 0.14, 0.24)
        s.shoulderWidth = share(l.shoulderWidth, 0.16, 0.30)
        s.hipWidth = share(l.hipWidth, 0.10, 0.24)
        s.torso = share(l.torso, 0.22, 0.38)
        s.thigh = share(l.thigh, 0.18, 0.32)
        s.shin = share(l.shin, 0.16, 0.30)
        s.headRadius = share(l.head, 0.04, 0.08) * 0.8
        s.measured = true
        return s
    }
}
