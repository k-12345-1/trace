import Foundation
import CoreGraphics

/// How much a leak is costing. Magnitude, not state, so it maps onto the ember ramp.
enum Severity: Int, Codable, Comparable {
    case negligible = 0, minor, moderate, costly, dominant
    static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }

    var label: String {
        switch self {
        case .negligible: return "Negligible"
        case .minor:      return "Minor"
        case .moderate:   return "Moderate"
        case .costly:     return "Costly"
        case .dominant:   return "Dominant"
        }
    }
}

enum LeakKind: String, Codable {
    case bentArms, weightOnArms, lurchy, impreciseFeet, hesitation, wandering
    case mistimedDynamics, unopposed

    var title: String {
        switch self {
        case .bentArms:         return "Bent arms while static"
        case .weightOnArms:     return "Weight hanging off your arms"
        case .lurchy:           return "Start-stop movement"
        case .impreciseFeet:    return "Imprecise feet"
        case .hesitation:       return "Reading the route while hanging on it"
        case .wandering:        return "The long way between moves"
        case .mistimedDynamics: return "Catching outside the deadpoint"
        case .unopposed:        return "Hanging outside your contacts"
        }
    }

    /// The correction, in one imperative sentence.
    ///
    /// The drill below is what to practise later. This is what to do on the
    /// next move, and it is the thing somebody looking at a picture of their
    /// own mistake actually wants: not what went wrong, which they can now see,
    /// but what the right version of it looks like.
    var instead: String {
        switch self {
        case .bentArms:
            return "Hang off straight arms between moves. Bend them only to pull."
        case .weightOnArms:
            return "Turn a hip in and get your weight over your feet before you reach."
        case .lurchy:
            return "Keep moving through the sequence instead of stopping on each hold."
        case .impreciseFeet:
            return "Look at the foothold until your shoe is on it, then leave it there."
        case .hesitation:
            return "Read the next two moves from a rest, not while hanging on."
        case .wandering:
            return "Go straight to the next hold instead of setting off and correcting."
        case .mistimedDynamics:
            return "Catch the hold at the top of the arc, not on the way up to it."
        case .unopposed:
            return "Put a foot or a hand out on the other side before you reach."
        }
    }

    /// A diagnosis with no prescription is a complaint.
    var drill: String {
        switch self {
        case .bentArms:
            return "Straight-arm traverse. Climb an easy traverse with your elbows never bending past 150 degrees."
        case .weightOnArms:
            return "Hip-turn drill. Turn a hip into the wall before every reach, on terrain two grades below your limit."
        case .lurchy:
            return "Downclimb everything you climb. It forces control and doubles your volume."
        case .impreciseFeet:
            return "Silent feet. Place each foot once, with no noise and no adjusting."
        case .hesitation:
            return "Read the whole sequence from the ground, then climb it without stopping."
        case .wandering:
            return "Climb it again and get from each position to the next in one movement, rather than setting off and correcting."
        case .mistimedDynamics:
            return "Deadpoint isolation. Pick one dynamic move and repeat it, catching the hold at the exact top of the arc rather than on the way up or the way down."
        case .unopposed:
            return "Find the second force. Before the reach, put a foot out on the side you are about to swing toward, or press into a hold with the hand that is not moving. A flag is not for balance, it is the other half of a pair."
        }
    }
}

struct Finding: Codable, Identifiable {
    var id = UUID()
    var kind: LeakKind
    var severity: Severity
    var start: Double
    var end: Double
    var message: String

    var timecode: String {
        let m = Int(start) / 60, s = Int(start) % 60
        return String(format: "%d:%02d", m, s)
    }
    var duration: Double { max(0, end - start) }

    /// The instant worth looking at: the middle of the window, capped so a long
    /// finding is still illustrated by its beginning. The still and the marks
    /// drawn on it both come from here, so they can never be a second apart.
    var lookAt: Double { start + min(duration / 2, 0.6) }
}

/// Everything the analysis produced for one climb.
struct Metrics: Codable {
    var entropy: Double            // geometric index of entropy, ln(2L/C). Lower is smoother.
    var logJerk: Double            // log dimensionless jerk. Lower is smoother.
    var pathRatio: Double          // COM path length over straight-line distance
    var staticElbowAngle: Double   // mean elbow angle in degrees while the COM is near-still
    var pauseCount: Int
    var pauseTotal: Double
    var footAdjustments: Int
    var comOffsetFromFeet: Double  // torso lengths the COM sits sideways of the feet
    var deadpointOffsets: [Double] // seconds, signed. Negative early, positive late.
    var comPath: [CGPoint]
    var duration: Double
    var trackingConfidence: Double // 0 to 1, fraction of frames with a usable skeleton
    /// Share of tracked time the center of mass sat between the outermost
    /// contacts, which is the whole of opposition reduced to one number.
    var bracketedFraction: Double = 0
    /// Share of tracked time spent squeezing between two wide hands.
    var compressionFraction: Double = 0
    /// Seconds held outside the contacts, long enough to be a position rather
    /// than a moment in transit.
    var swingTotal: Double = 0
    /// Share of everything travelled that was not toward the next position.
    ///
    /// This replaced the path ratio as the measure of a wandering line, because
    /// the path ratio compared a boulder against a straight line up the wall
    /// and no boulder offers one. Optional rather than zero, because a climb
    /// with too few moves to read and a climb with no detours in it are
    /// different answers and only one of them is good news.
    var moveWaste: Double?
    /// Smoothness measured between the rests, the middle value of the spans.
    ///
    /// This replaced `logJerk` for every comparison Trace makes. Log
    /// dimensionless jerk over a whole climb multiplies by the fifth power of
    /// the duration and divides by the path length squared, so a rest, which
    /// adds duration and no length, makes the same movement score as far
    /// jerkier. Two findings then came off one behaviour.
    ///
    /// Optional, and old climbs have none. A number measured the old way is not
    /// comparable with one measured this way, and quietly mixing them is
    /// exactly the mistake this field exists to stop.
    var movingJerk: Double?

    /// Below this we do not draw and we do not coach. Confidently wrong feedback
    /// is the failure mode that kills the product.
    var isTrustworthy: Bool { trackingConfidence >= 0.55 }

    /// Mean timing error on dynamic moves, in milliseconds. Zero when the climb
    /// had no dynamic moves to judge, which is not the same as perfect timing.
    var meanDeadpointError: Double {
        guard !deadpointOffsets.isEmpty else { return 0 }
        let total = deadpointOffsets.reduce(0.0) { $0 + abs($1) }
        return total / Double(deadpointOffsets.count) * 1000
    }

    /// Positive means catching late, on the way back down.
    var deadpointBias: Double {
        guard !deadpointOffsets.isEmpty else { return 0 }
        return deadpointOffsets.reduce(0, +) / Double(deadpointOffsets.count) * 1000
    }

    var hasDynamicMoves: Bool { !deadpointOffsets.isEmpty }

    // Decoded leniently so that adding a metric does not throw away a climber's
    // stored history. Anything missing from an older file falls back to a neutral
    // value rather than failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entropy            = try c.decode(Double.self, forKey: .entropy)
        logJerk            = try c.decode(Double.self, forKey: .logJerk)
        pathRatio          = try c.decode(Double.self, forKey: .pathRatio)
        staticElbowAngle   = try c.decode(Double.self, forKey: .staticElbowAngle)
        pauseCount         = try c.decode(Int.self, forKey: .pauseCount)
        pauseTotal         = try c.decode(Double.self, forKey: .pauseTotal)
        footAdjustments    = try c.decode(Int.self, forKey: .footAdjustments)
        comPath            = try c.decode([CGPoint].self, forKey: .comPath)
        duration           = try c.decode(Double.self, forKey: .duration)
        trackingConfidence = try c.decode(Double.self, forKey: .trackingConfidence)
        comOffsetFromFeet  = try c.decodeIfPresent(Double.self, forKey: .comOffsetFromFeet) ?? 0
        deadpointOffsets   = try c.decodeIfPresent([Double].self, forKey: .deadpointOffsets) ?? []
        bracketedFraction  = try c.decodeIfPresent(Double.self, forKey: .bracketedFraction) ?? 0
        compressionFraction = try c.decodeIfPresent(Double.self, forKey: .compressionFraction) ?? 0
        swingTotal         = try c.decodeIfPresent(Double.self, forKey: .swingTotal) ?? 0
        // Nil rather than zero when it is missing. A climb analyzed before this
        // existed has no reading, and zero would mean a perfect one.
        moveWaste          = try c.decodeIfPresent(Double.self, forKey: .moveWaste)
        movingJerk         = try c.decodeIfPresent(Double.self, forKey: .movingJerk)
    }

    init(entropy: Double, logJerk: Double, pathRatio: Double, staticElbowAngle: Double,
         pauseCount: Int, pauseTotal: Double, footAdjustments: Int,
         comOffsetFromFeet: Double = 0, deadpointOffsets: [Double] = [],
         comPath: [CGPoint], duration: Double, trackingConfidence: Double,
         bracketedFraction: Double = 0, compressionFraction: Double = 0,
         swingTotal: Double = 0, moveWaste: Double? = nil,
         movingJerk: Double? = nil) {
        self.bracketedFraction = bracketedFraction
        self.compressionFraction = compressionFraction
        self.swingTotal = swingTotal
        self.moveWaste = moveWaste
        self.movingJerk = movingJerk
        self.entropy = entropy
        self.logJerk = logJerk
        self.pathRatio = pathRatio
        self.staticElbowAngle = staticElbowAngle
        self.pauseCount = pauseCount
        self.pauseTotal = pauseTotal
        self.footAdjustments = footAdjustments
        self.comOffsetFromFeet = comOffsetFromFeet
        self.deadpointOffsets = deadpointOffsets
        self.comPath = comPath
        self.duration = duration
        self.trackingConfidence = trackingConfidence
    }
}

struct Climb: Codable, Identifiable {
    var id = UUID()
    var recordedAt: Date
    var videoFilename: String
    var label: String              // free text, user typed, never validated against anything
    var metrics: Metrics
    var findings: [Finding]
    var frames: [PoseFrame]
    /// Whether this attempt topped out. Optional rather than defaulted so that
    /// climbs recorded before the field existed still decode: Swift's synthesized
    /// decoder ignores a property's default and throws on a missing key.
    var sent: Bool?
    /// The gym you were in. Optional for the same reason, and also because it
    /// genuinely can be unknown: every climb recorded before this existed has no
    /// answer, and a climb filmed outdoors never will.
    var gymID: UUID?
    /// What the climber said about it, which is the half the camera cannot see.
    /// Nil until they say something, so silence is not stored as a set of
    /// middling scores.
    var notes: ClimbNotes?

    var isSent: Bool { sent == true }

    var videoURL: URL { Store.videosDirectory.appendingPathComponent(videoFilename) }
}
