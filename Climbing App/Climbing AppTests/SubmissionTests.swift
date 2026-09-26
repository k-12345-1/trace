import Testing
import Foundation
import SwiftUI
@testable import ClimbingApp

/// The things that stop a build reaching the App Store, asserted rather than
/// remembered.
///
/// Each of these was a real defect found while going through the project against
/// Apple's requirements, and each of them is invisible: the app compiles, runs,
/// and looks finished with every one of them in place. A test is the only thing
/// that notices them coming back.
// Serialized: these share `Store.shared`, and run in parallel one test's wipe
// lands in the middle of another's setup.
@Suite("Ready to submit", .serialized) @MainActor
struct SubmissionTests {

    // MARK: A way into the app

    /// The one that mattered most. `AppEntry` shows the welcome screen until an
    /// account exists, and with no auth server the only two ways to make one
    /// were a sign-up that throws `notConfigured` and a hardcoded demo pair. A
    /// climber who downloaded Trace could not get past the first screen.
    ///
    /// This asserts the state the app has to reach, which is the state
    /// `AppEntry` reads: an account, and an answer to the stay-signed-in
    /// question. An account with that question still open shows the question
    /// instead of the app, and for a local account there is no session to keep,
    /// so asking it would be asking about nothing.
    @Test("Starting with no account reaches the app")
    func startingLocallyReachesTheApp() {
        let store = Store.shared
        store.continueLocally(name: "Katie")

        #expect(store.account != nil)
        #expect(store.account?.isLocalOnly == true)
        #expect(store.staySignedIn != nil, "the app would stop on Stay signed in?")
        #expect(store.account?.displayName == "Katie")
    }

    /// The name is optional, and an empty one must not leave the profile
    /// greeting blank.
    @Test("A climber who skips the name is still called something")
    func anEmptyNameStillHasADisplayName() {
        Store.shared.continueLocally(name: "   ")
        #expect(Store.shared.account?.displayName == "Climber")
    }

    /// Which welcome screen shows is a function of whether anything can issue an
    /// account, so the credential screens appear on their own the moment a
    /// server is configured and not before.
    @Test("Accounts off means the local start screen")
    func theWelcomeScreenFollowsTheConfiguration() {
        let saved = AuthClient.config
        defer { AuthClient.config = saved }

        AuthClient.config = .init(url: "", anonKey: "")
        #expect(AuthClient.isConfigured == false)

        AuthClient.config = .init(url: "https://example.supabase.co", anonKey: "anon")
        #expect(AuthClient.isConfigured == true)

        // Not https, so not configured: a token sent in clear is worse than no
        // account at all.
        AuthClient.config = .init(url: "http://example.supabase.co", anonKey: "anon")
        #expect(AuthClient.isConfigured == false)
    }

    // MARK: Deleting an account

    /// A local account has no server to call, so deleting must not depend on
    /// one, and it must actually remove what it says it removes.
    @Test("Deleting a local account takes the phone with it")
    func deletingALocalAccountWipesThePhone() async throws {
        let store = Store.shared
        store.continueLocally(name: "Katie")
        store.updateBody(BodyProfile(heightCM: 170, spanCM: 172, massKG: 62,
                                     usesImperial: false))

        try await store.deleteAccount()

        #expect(store.account == nil)
        #expect(store.climbs.isEmpty)
        #expect(store.body.heightCM == nil, "the measurements outlived the account")
    }

    /// The half of it Apple actually rejects for, and the half that is dangerous
    /// to get wrong in the other direction. If the account record cannot be
    /// deleted, nothing local may be touched: an account that outlives every
    /// trace of itself on the only device that knew about it is unreachable, and
    /// the person has no way left to ask for it again.
    @Test("A failed server delete leaves the phone alone")
    func aFailedDeleteChangesNothing() async {
        let store = Store.shared
        let savedConfig = AuthClient.config
        defer { AuthClient.config = savedConfig }

        // A port nothing is listening on, so the call fails at once rather than
        // spending the request timeout.
        AuthClient.config = .init(url: "https://127.0.0.1:9", anonKey: "anon")
        store.signedIn(session: Session(accessToken: "a", refreshToken: "r",
                                        expiresAt: .distantFuture,
                                        userID: "u", email: "climber@example.com"),
                       name: "Katie")
        store.updateBody(BodyProfile(heightCM: 170, spanCM: 172, massKG: 62,
                                     usesImperial: false))

        await #expect(throws: (any Error).self) { try await store.deleteAccount() }

        #expect(store.account != nil, "the account was cleared on a failed delete")
        #expect(store.body.heightCM == 170, "the measurements were wiped anyway")

        store.continueLocally(name: "Katie")
        try? await store.deleteAccount()
    }

    // MARK: The privacy manifest

    /// Missing entirely until this was written, which is an ITMS-91053 notice on
    /// every upload rather than a rejection, and a notice that becomes a
    /// rejection.
    @Test("The build carries a privacy manifest")
    func thePrivacyManifestShips() throws {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "PrivacyInfo",
                                              withExtension: "xcprivacy")
                ?? Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "no PrivacyInfo.xcprivacy in the bundle")
        let manifest = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil) as? [String: Any])

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)

        // UserDefaults is a required-reason API, and Trace reads it: the muted
        // preference on the clip player, and the saved session flag.
        let apis = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let defaults = apis.first {
            $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = try #require(defaults?["NSPrivacyAccessedAPITypeReasons"] as? [String],
                                   "UserDefaults is used and undeclared")
        #expect(reasons.contains("CA92.1"))
    }

    // MARK: What the policy claims

    /// The policy said gym logos were the only thing that ever leaves the phone,
    /// while the place field sent what you typed to Apple Maps. A document that
    /// is wrong about the code is worse than one that is vague, and the App
    /// Privacy answers have to match it.
    @Test("The policy names everything that leaves the phone")
    func theP0licyNamesThePlaceSearch() {
        let prose = LegalScreen.privacy().sections
            .flatMap(\.body).joined(separator: " ")

        #expect(prose.contains("Apple Maps"),
                "the place completions are undisclosed")
        #expect(prose.contains("Gym logos"))
        #expect(prose.contains("Purchases are handled by Apple"))
        #expect(!prose.contains("It is the only thing that has ever been added"),
                "the policy still claims logos are the only thing that leaves")
    }

    /// The version at the top of both documents is what a support question about
    /// "which terms did I agree to" is answered with, so it has to move when
    /// the words do.
    @Test("The legal version moved with the words")
    func theLegalVersionMoved() {
        #expect(LegalScreen.version != "1.1")
    }
}

/// Somewhere to hang the test bundle from, so the manifest can be found whether
/// the tests are hosted in the app or running on their own.
private final class BundleToken {}
