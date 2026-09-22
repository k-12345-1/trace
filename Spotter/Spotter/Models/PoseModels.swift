import Foundation
import CoreGraphics

/// A single tracked joint in normalised image space, origin top-left, y increasing downward.
struct Joint: Codable, Hashable {
    var x: Double
    var y: Double
    var confidence: Double

    var point: CGPoint { CGPoint(x: x, y: y) }
    var isUsable: Bool { confidence >= 0.25 }
}

/// The joints Spotter cares about. Vision reports more, but faces and fingertips
/// tell us nothing about movement economy.
enum JointID: String, Codable, CaseIterable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case root
}

/// One frame of tracking.
struct PoseFrame: Codable {
    var time: Double                       // seconds from clip start
    var joints: [JointID: Joint]
    var com: CGPoint?                      // centre of mass, normalised
    var meanConfidence: Double

    func pt(_ id: JointID) -> CGPoint? {
        guard let j = joints[id], j.isUsable else { return nil }
        return j.point
    }
}

// CGPoint needs Codable conformance for persistence.
extension CGPoint: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let x = try c.decode(Double.self)
        let y = try c.decode(Double.self)
        self.init(x: x, y: y)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(Double(x))
        try c.encode(Double(y))
    }
}

/// The skeleton segments we draw. Kept here so the overlay and the analysis agree.
enum Skeleton {
    static let bones: [(JointID, JointID)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
    static let dots: [JointID] = [
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]
}
