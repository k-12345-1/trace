import Testing
import Foundation
@testable import ClimbingApp

/// Where the hips were when a reach across set off.
@Suite("Hips on the reach")
struct HipsBehindTests {
    /// A climber with the left hand on a hold, reaching right with the right
    /// hand. `hipsX` is where the hips sit at the start and the end.
    private func frames(hipsStart: Double, hipsEnd: Double) -> [PoseFrame] {
        (0...10).map { i in
            let u = Double(i) / 10
            let hipsX = hipsStart + (hipsEnd - hipsStart) * u
            var f = PoseFrame(time: u, joints: [:], com: CGPoint(x: hipsX, y: 0.6), meanConfidence: 1)
            f.joints[.leftWrist] = Joint(x: 0.4, y: 0.4, confidence: 1)
            // The right hand goes from beside the left to a hold well to the right.
            f.joints[.rightWrist] = Joint(x: 0.45 + 0.25 * u, y: 0.4 - 0.1 * u, confidence: 1)
            f.joints[.leftHip] = Joint(x: hipsX - 0.04, y: 0.6, confidence: 1)
            f.joints[.rightHip] = Joint(x: hipsX + 0.04, y: 0.6, confidence: 1)
            return f
        }
    }
    private let reach = ReachEngine.Reach(hand: .rightWrist, start: 0, end: 1, travelled: 1.3, carried: 0.2,
                                          share: 0.15, catchElbow: nil, hipOpenness: nil, supportingElbow: nil)
    private let torso = 0.2

    @Test("Hips left on the far side of the other hand are behind")
    func hipsLeftBehind() throws {
        // Hips a third of a torso left of the left hand, and they stay there.
        let lead = try #require(TechniqueEngine.hipsLead(of: reach, in: frames(hipsStart: 0.33, hipsEnd: 0.34), torso: torso))
        #expect(lead.behind)
        #expect(lead.from < -TechniqueEngine.hipsBehindBy)
    }

    @Test("Hips that come across first are not behind")
    func hipsLedAcross() throws {
        let led = try #require(TechniqueEngine.hipsLead(of: reach, in: frames(hipsStart: 0.33, hipsEnd: 0.45), torso: torso))
        #expect(!led.behind)
        #expect(led.toward >= TechniqueEngine.hipsLeadBy)
        // And hips already under the reaching side were never behind.
        let under = try #require(TechniqueEngine.hipsLead(of: reach, in: frames(hipsStart: 0.5, hipsEnd: 0.5), torso: torso))
        #expect(!under.behind)
    }

    @Test("A reach straight up is not judged")
    func straightUpIsNotJudged() {
        var f = frames(hipsStart: 0.33, hipsEnd: 0.33)
        for i in f.indices { f[i].joints[.rightWrist] = Joint(x: 0.42, y: 0.4 - 0.1 * Double(i) / 10, confidence: 1) }
        #expect(TechniqueEngine.hipsLead(of: reach, in: f, torso: torso) == nil)
    }
}
