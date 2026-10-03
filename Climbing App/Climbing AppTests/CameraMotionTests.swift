import Testing
import Foundation
import CoreVideo
import CoreGraphics
@testable import ClimbingApp

private final class BundleToken {}

/// Whether the phone stayed put.
///
/// Every spatial measurement in Trace is computed from where the body went
/// inside the frame, and all of them assume the frame is a fixed window onto
/// the wall. Nothing checked it, and the footage people will most naturally
/// import is the kind that breaks it: somebody following you up the wall.
///
/// On the four real clips available, the one filmed from the floor moved the
/// picture 0.01 frame heights over thirty seconds. The three handheld ones moved
/// it 1.74, 1.87 and 2.96. The second of those is a climber who went up a whole
/// wall, and Trace graded her "very inefficient, 82% wasted", 78 points of which
/// were "your height was gained twice" as the operator bobbed.
@Suite("Camera motion")
struct CameraMotionTests {

    /// A still clip, registered against itself.
    ///
    /// The fixture is three seconds of a real climb filmed from the floor, which
    /// is the only footage in the repository and the only kind Trace asks for.
    @Test("A phone on the floor reads as still")
    func aStillPhoneReadsAsStill() async throws {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "climber", withExtension: "mp4"))
        let reading = try #require(await CameraMotion.read(url: url))

        #expect(reading.confidence > 0.8, "registered only \(reading.confidence)")
        #expect(reading.travel < CameraMotion.staticTravel,
                "travelled \(reading.travel) frame heights")
        #expect(reading.isStatic)
    }

    /// The threshold sits clear of both sides rather than splitting them.
    @Test("The threshold is not a split difference")
    func theThresholdHasRoomEitherSide() {
        // Measured: still 0.01, handheld 1.74, 1.87, 2.96.
        #expect(CameraMotion.staticTravel > 0.01 * 10)
        #expect(CameraMotion.staticTravel < 1.74 / 4)
    }

    /// A reading with too few registered pairs says nothing rather than "still".
    @Test("Unregistrable footage is not called still")
    func lowConfidenceIsNotStill() {
        let unsure = CameraMotion.Reading(travel: 0.001, drift: 0, confidence: 0.2)
        #expect(!unsure.isStatic)
        let sure = CameraMotion.Reading(travel: 0.001, drift: 0, confidence: 0.99)
        #expect(sure.isStatic)
    }

    // MARK: Steadying the skeleton

    /// Vision answers with the transform that lays the new frame over the old
    /// one, which is the opposite of where the picture went. The sign is
    /// settled here, on a picture moved a known distance, not by reading.
    @Test("The shift is where the picture went")
    func theShiftIsWhereThePictureWent() throws {
        let before = try #require(Self.picture(movedDownBy: 0, rightBy: 0))
        let after = try #require(Self.picture(movedDownBy: 12, rightBy: 7))
        let moved = try #require(CameraMotion.shift(from: before, to: after))
        #expect(abs(moved.y - 12) <= 1.5, "read \(moved) for a picture moved down 12")
        #expect(abs(moved.x - 7) <= 1.5, "read \(moved) for a picture moved right 7")
    }

    /// A climber tracked on a phone that panned up the wall is put back
    /// where the wall is.
    @Test("Steadied frames take the phone's movement back out")
    func steadiedFramesTakeThePhoneOut() {
        // The picture travelled a tenth of the frame downward over a second,
        // which is the phone tilting up to follow.
        let reading = CameraMotion.Reading(travel: 0.1, drift: 0.1, confidence: 1, path: [
            .init(time: 0, dx: 0, dy: 0), .init(time: 1, dx: 0, dy: 0.1)])
        var frame = PoseFrame(time: 0.5, joints: [:], com: CGPoint(x: 0.5, y: 0.5), meanConfidence: 1)
        frame.joints[.leftWrist] = Joint(x: 0.4, y: 0.3, confidence: 1)
        let out = CameraMotion.stabilized([frame], by: reading)
        #expect(abs((out[0].com?.y ?? 0) - 0.45) < 1e-9)
        #expect(abs((out[0].pt(.leftWrist)?.y ?? 0) - 0.25) < 1e-9)
        #expect(abs((out[0].pt(.leftWrist)?.x ?? 0) - 0.4) < 1e-9)
        // An older reading, with no path, changes nothing.
        let old = CameraMotion.Reading(travel: 2, drift: 1, confidence: 1)
        #expect(CameraMotion.stabilized([frame], by: old)[0].com == frame.com)
    }

    /// A busy picture, drawn with a fixed scatter of blocks, moved down the
    /// buffer by `dy` rows and right by `dx` columns.
    static func picture(movedDownBy dy: Int, rightBy dx: Int) -> CVPixelBuffer? {
        let w = 180, h = 320
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true,
                             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &made)
        guard let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(gray: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Core Graphics counts rows upward from the bottom of the buffer, so
        // moving content down the buffer is drawing it lower in CG.
        var seed: UInt64 = 7
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        for _ in 0..<60 {
            let x = next() % (w - 40) + 15, y = next() % (h - 60) + 30, size = 4 + next() % 9
            ctx.setFillColor(gray: CGFloat(next() % 100) / 100, alpha: 1)
            ctx.fill(CGRect(x: x + dx, y: y - dy, width: size, height: size))
        }
        return buffer
    }

    // MARK: What the climb does with it

    @Test("A climb remembers whether the phone moved")
    func theClimbRemembers() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        #expect(climb.cameraWasStill == nil, "unknown is not the same as still")

        climb.cameraTravel = 0.01
        #expect(climb.cameraWasStill == true)

        climb.cameraTravel = 1.74
        #expect(climb.cameraWasStill == false)
    }

    /// A climb recorded before any of this existed decodes, and says it does not
    /// know rather than claiming the phone was still.
    @Test("An older climb decodes as unknown")
    func anOlderClimbDecodesAsUnknown() throws {
        let climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(try JSONSerialization.jsonObject(
            with: try encoder.encode(climb)) as? [String: Any])
        json.removeValue(forKey: "cameraTravel")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(Climb.self,
                                      from: try JSONSerialization.data(withJSONObject: json))
        #expect(back.cameraTravel == nil)
        #expect(back.cameraWasStill == nil)
    }

    // MARK: What the screen does with it

    /// A moving camera is shown as its own thing, not as "I could not see that
    /// one clearly", because Trace saw it perfectly.
    @Test("A moving camera is explained, not graded")
    func theScreenExplainsRatherThanGrades() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.cameraTravel = 1.74
        #expect(ResultsReadout.of(climb) == .cameraMoved)
    }

    @Test("A climb filmed from the floor is read as before")
    func aStillClimbIsUnaffected() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.cameraTravel = 0.01
        #expect(ResultsReadout.of(climb) == .measurements)
    }

    /// A climb from before any of this is read as before, rather than being
    /// withheld on a suspicion.
    @Test("An unknown camera is not treated as a moving one")
    func unknownIsNotMoving() {
        let climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        #expect(climb.cameraTravel == nil)
        #expect(ResultsReadout.of(climb) == .measurements)
    }

    /// The order is an argument, so it is asserted. A clip that is both filmed
    /// on a moving phone and badly tracked is reported as the first, because
    /// "I could not see you" is the wrong sentence when Trace saw it fine.
    @Test("A moving camera outranks poor tracking")
    func theCameraComesFirst() {
        var climb = Fixture.climb(path: Fixture.straightPath(), entropy: 1)
        climb.metrics.trackingConfidence = 0.1
        #expect(ResultsReadout.of(climb) == .unreadable)
        climb.cameraTravel = 2.0
        #expect(ResultsReadout.of(climb) == .cameraMoved)
    }


}

/// Where the accounts live, and what happens when they do not.
@Suite("Supabase configuration")
struct SupabaseConfigTests {

    /// The URL is set, so the moment a key lands the app has a server.
    @Test("The project URL is set and is https")
    func theURLIsSet() {
        #expect(SupabaseConfig.url.hasPrefix("https://"))
        #expect(SupabaseConfig.url.contains(".supabase.co"))
    }

    /// The service role key bypasses every policy and anyone can pull it out of
    /// a shipped binary. Nothing in Trace should ever hold one, which is why
    /// deleting an account goes through a security-definer function instead.
    ///
    /// A Supabase JWT carries its role in the payload, so this reads it rather
    /// than trusting the variable's name.
    @Test("No service role key is compiled in")
    func noServiceRoleKey() throws {
        let key = SupabaseConfig.anonKey
        try #require(!key.isEmpty || key.isEmpty)   // either state is valid
        guard !key.isEmpty else { return }

        let parts = key.split(separator: ".")
        // Newer publishable keys are not JWTs at all, and cannot be service keys.
        guard parts.count == 3 else {
            #expect(!key.contains("service_role"))
            return
        }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        let data = try #require(Data(base64Encoded: payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["role"] as? String != "service_role",
                "a service role key is compiled into the app")
    }

    /// Both halves are needed, so a half-filled configuration is off rather
    /// than half on, and the app stays in local-only mode instead of throwing
    /// at a climber trying to sign in.
    @Test("Half a configuration is no configuration")
    func halfIsOff() {
        let saved = AuthClient.config
        defer { AuthClient.config = saved }

        AuthClient.config = .init(url: SupabaseConfig.url, anonKey: "")
        #expect(!AuthClient.isConfigured)
        AuthClient.config = .init(url: "", anonKey: "some-key")
        #expect(!AuthClient.isConfigured)
        AuthClient.config = .init(url: SupabaseConfig.url, anonKey: "some-key")
        #expect(AuthClient.isConfigured)
    }
}
