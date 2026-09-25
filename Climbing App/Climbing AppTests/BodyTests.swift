import Testing
import Foundation
import CoreGraphics
@testable import ClimbingApp

// MARK: - The two numbers

@Suite("Body profile")
struct BodyProfileTests {

    @Test("Feet and inches survive the round trip through centimetres")
    func roundTrip() {
        for (feet, inches) in [(5, 0.0), (5, 7.5), (6, 2.0), (4, 11.5)] {
            let cm = BodyProfile.cm(feet: feet, inches: inches)
            let back = BodyProfile.feetInches(fromCM: cm)
            #expect(back.feet == feet)
            #expect(abs(back.inches - inches) < 0.01)
        }
    }

    @Test("Eleven and three quarter inches rounds up into the next foot")
    func inchesCarry() {
        // 5 ft 11.9 in rounds to 12 inches, which is 6 ft rather than 5 ft 12.
        let cm = BodyProfile.cm(feet: 5, inches: 11.9)
        let back = BodyProfile.feetInches(fromCM: cm)
        #expect(back.feet == 6)
        #expect(back.inches == 0)
    }

    @Test("Ape index is reach minus height, signed")
    func apeIndex() {
        // Units are stated rather than left to the default, which follows the
        // device locale and so differs between machines.
        var plus = BodyProfile(heightCM: 170, spanCM: 176, usesImperial: false)
        #expect(plus.apeIndexCM == 6)
        #expect(plus.apeIndexLabel == "+6 cm")

        plus.usesImperial = true
        // 6 cm is 2.36 inches, shown to one place.
        #expect(plus.apeIndexLabel == "+2.4 in")

        let minus = BodyProfile(heightCM: 180, spanCM: 174, usesImperial: false)
        #expect(minus.apeIndexCM == -6)
        #expect(minus.apeIndexLabel == "-6 cm")
    }

    @Test("Ape index needs both numbers")
    func apeIndexNeedsBoth() {
        #expect(BodyProfile(heightCM: 170, spanCM: nil).apeIndexCM == nil)
        #expect(BodyProfile(heightCM: nil, spanCM: 176).apeIndexCM == nil)
    }

    @Test("Implausible measurements are refused")
    func plausibility() {
        // The common mistake is typing inches into the centimetres box.
        #expect(!BodyProfile.plausibleHeight(68))
        #expect(!BodyProfile.plausibleHeight(1.7))
        #expect(BodyProfile.plausibleHeight(170))
        #expect(BodyProfile.plausibleSpan(255))
        #expect(!BodyProfile.plausibleSpan(300))
    }

    @Test("An unset measurement says so rather than showing zero")
    func describesUnset() {
        #expect(BodyProfile(usesImperial: false).describe(nil) == "Not set")
        #expect(BodyProfile(heightCM: 170, usesImperial: false).describe(170) == "170 cm")
        #expect(BodyProfile(heightCM: 170, usesImperial: true).describe(182.88) == "6′ 0″")
    }
}

// MARK: - Pixels into meters

@Suite("Body scale")
struct BodyScaleTests {

    /// A climber of a known tracked extent, so the arithmetic has a known answer.
    private func frames(extent: Double, count: Int = 30,
                        shrinkLast: Double? = nil) -> [PoseFrame] {
        (0..<count).map { i in
            let e = (shrinkLast != nil && i >= count - 2) ? shrinkLast! : extent
            var joints: [JointID: Joint] = [:]
            joints[.nose] = Joint(x: 0.5, y: 0.5 - e / 2, confidence: 0.9)
            joints[.leftShoulder] = Joint(x: 0.45, y: 0.5 - e / 4, confidence: 0.9)
            joints[.rightShoulder] = Joint(x: 0.55, y: 0.5 - e / 4, confidence: 0.9)
            joints[.leftHip] = Joint(x: 0.47, y: 0.5, confidence: 0.9)
            joints[.rightHip] = Joint(x: 0.53, y: 0.5, confidence: 0.9)
            joints[.leftAnkle] = Joint(x: 0.47, y: 0.5 + e / 2, confidence: 0.9)
            joints[.rightAnkle] = Joint(x: 0.53, y: 0.5 + e / 2, confidence: 0.9)
            return PoseFrame(time: Double(i) / 30, joints: joints,
                             com: CGPoint(x: 0.5, y: 0.5), meanConfidence: 0.9)
        }
    }

    @Test("No height means no scale, and that is not an error")
    func noHeightNoScale() {
        #expect(BodyScale.metersPerUnit(frames: frames(extent: 0.5),
                                        body: .empty) == nil)
        #expect(BodyScale.metersPerUnit(frames: [], body: BodyProfile(heightCM: 170)) == nil)
    }

    @Test("A climber filling half the frame gets the expected scale")
    func knownScale() {
        // Tracked extent 0.5 of frame height is 0.89 x 1.70 m of real body,
        // so one unit of frame height is 1.513 / 0.5 = 3.026 m.
        let mpu = BodyScale.metersPerUnit(frames: frames(extent: 0.5),
                                          body: BodyProfile(heightCM: 170))
        #expect(mpu != nil)
        #expect(abs(mpu! - (1.70 * 0.89) / 0.5) < 0.0001)
    }

    @Test("A taller climber at the same distance reads a larger scale")
    func tallerIsLarger() {
        let short = BodyScale.metersPerUnit(frames: frames(extent: 0.5),
                                            body: BodyProfile(heightCM: 160))!
        let tall = BodyScale.metersPerUnit(frames: frames(extent: 0.5),
                                           body: BodyProfile(heightCM: 190))!
        #expect(tall > short)
    }

    @Test("One collapsed frame does not shrink the estimate")
    func percentileIgnoresOutliers() {
        // Two frames of the thirty show the climber curled up. The 95th
        // percentile should still report the extended figure.
        let clean = BodyScale.extendedExtent(frames: frames(extent: 0.5))!
        let withCrouch = BodyScale.extendedExtent(
            frames: frames(extent: 0.5, shrinkLast: 0.2))!
        #expect(abs(clean - withCrouch) < 0.001)
    }

    @Test("Reach radius is half the span in image units")
    func reachRadius() {
        let body = BodyProfile(heightCM: 170, spanCM: 180)
        let mpu = BodyScale.metersPerUnit(frames: frames(extent: 0.5), body: body)!
        let radius = BodyScale.reachRadius(frames: frames(extent: 0.5), body: body)!
        // 0.90 m of arm, converted back through the scale.
        #expect(abs(radius - 0.90 / mpu) < 0.0001)
    }

    @Test("Reach radius needs a span, not just a height")
    func reachNeedsSpan() {
        #expect(BodyScale.reachRadius(frames: frames(extent: 0.5),
                                      body: BodyProfile(heightCM: 170)) == nil)
    }

    @Test("Speed converts only when there is a scale")
    func speedConversion() {
        #expect(BodyScale.metersPerSecond(0.2, metersPerUnit: nil) == nil)
        let m = BodyScale.metersPerSecond(0.2, metersPerUnit: 3.0)
        #expect(m != nil && abs(m! - 0.6) < 0.0001)
    }
}
