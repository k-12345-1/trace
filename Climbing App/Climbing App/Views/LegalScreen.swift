import SwiftUI

/// The two documents, readable inside the app.
///
/// They are held here as text rather than fetched from a website, which is the
/// only arrangement consistent with the rest of Trace: an app that promises to
/// reach the network for nothing should not need the network to show you its own
/// privacy policy.
///
/// The consequence is that the version someone agreed to is the version shipped
/// in the build they have, and a change to either document only reaches them in
/// an update. `version` below is what makes that checkable rather than vague.
struct LegalScreen: View {
    let title: String
    let updated: String
    let standfirst: String
    let sections: [Section]

    struct Section: Identifiable {
        let heading: String
        let body: [String]
        var id: String { heading }
    }

    /// Bumped whenever either document changes in a way that alters what a
    /// person agreed to. Shown at the top of both so a support question about
    /// "which terms" has an answer.
    static let version = "1.1"

    @Environment(\.dismiss) private var dismiss
    /// True when this is pushed inside the tabbed app, false when it is opened
    /// on its own from the sign-in screen or the paywall.
    var insideApp = true

    /// Set as a document rather than as a screen of interface, which is two
    /// departures from the rest of the app and both are deliberate.
    ///
    /// The type is sized in text styles rather than in fixed points, so these
    /// two documents are the only place in Trace that grows when someone has
    /// turned up text size in iOS. Every other screen is a fixed layout holding
    /// measurements. This one is prose, and prose a person is being asked to
    /// agree to has to be readable at whatever size they need it.
    ///
    /// And the sections are not cards. A card says "separate object", which is
    /// right for a finding and wrong for a paragraph: nine shadowed boxes down
    /// a column turn one continuous read into nine separate starts. A rule
    /// above each heading separates just as well without interrupting, and it
    /// leaves the paper showing behind the text.
    var body: some View {
        ZStack(alignment: .top) {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Space for the pinned header, which is not in this column.
                    Color.clear.frame(height: 52)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.system(.title, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Version \(Self.version) · \(updated)")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink3)
                        // The lede. Set larger than the body and in the same
                        // serif, so the first thing read is the easiest thing
                        // to read.
                        Text(standfirst)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(Theme.ink2)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 30)

                    VStack(alignment: .leading, spacing: 30) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 13) {
                                Hairline(color: Theme.lineStrong)
                                    .padding(.bottom, 4)
                                Text(section.heading)
                                    .font(.system(.title3, design: .serif).weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                // Paragraphs are spaced further apart than the
                                // lines inside them, which is the whole of what
                                // makes a paragraph break visible.
                                VStack(alignment: .leading, spacing: 15) {
                                    ForEach(Array(section.body.enumerated()), id: \.offset) { _, p in
                                        Text(p)
                                            .font(.system(.body, design: .serif))
                                            .foregroundStyle(Theme.ink)
                                            .lineSpacing(6)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                // Enough to clear the tab bar when this is pushed inside the
                // app, and no more. The fixed 156 that every screen behind the
                // bar carries left a blank third of a screen under the last
                // paragraph when the document opens on its own, where there is
                // no bar to clear.
                .padding(.bottom, insideApp ? 156 : 32)
            }
            .scrollIndicators(.hidden)

            // Pinned, not scrolled with the text. These are long documents, and
            // presented full screen there is no swipe back either, so a control
            // that disappears once you start reading is a way to get stuck.
            NavHeader(title: nil) { dismiss() }
                .background {
                    // Solid, and carried up through the status bar. Translucent,
                    // the paragraphs scrolling underneath ghost through it.
                    PaperBand()
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

// MARK: - Privacy Policy

extension LegalScreen {
    static func privacy(insideApp: Bool = true) -> LegalScreen {
        LegalScreen(
            title: "Privacy Policy",
            updated: "24 September 2026",
            standfirst: "Trace measures your climbing on your phone and uploads none of it. This policy exists to say exactly what that means, and to be honest about the three places where something does leave the device.",
            sections: [
                Section(heading: "What stays on your phone", body: [
                    "Your video clips, the pose data extracted from them, every measurement, every finding, your route photographs, the holds found in them, your gyms, and your height, reach and weight. All of it is written to this app's own storage on this device.",
                    "None of it is uploaded, backed up to us, or shared with anyone. We cannot read it. There is no server that holds it, so there is nothing for us to hand over, sell, lose, or be compelled to produce.",
                    "It is included in an encrypted iPhone backup if you make one, because that is how iOS backs up app data. That backup is between you and Apple."
                ]),
                Section(heading: "The analysis", body: [
                    "Pose estimation runs on the device using Apple's Vision framework. No frame of your footage is sent to us or to any other company for analysis.",
                    "Trace does not use a large language model. Nothing you record is used to train anything, ours or anyone else's."
                ]),
                Section(heading: "Your location", body: [
                    "The Explore screen can sort the list of climbing gyms by how near each one is to you. To do that it asks iOS where the phone is.",
                    "That coordinate is used on the device to sort a list that is already on the device, and it is not stored, not written to disk, and not sent anywhere. Saying no leaves the list in alphabetical order and costs you nothing else."
                ]),
                Section(heading: "What does leave the device", body: [
                    "Your account. Signing in sends your email address and password to our authentication provider so we can tell whether the person opening the app is you. We store your email address, when the account was made, and nothing else about you. We do not store your password: the provider holds a hash of it.",
                    "Your subscription. Purchases are handled by Apple. Apple tells the app whether a subscription is active. We never see your card, your billing address, or your Apple ID. We do not receive a payment record with your name on it.",
                    "Gym logos. Trace ships none: a gym's logo is theirs, and the only place it exists is on their own website. So the first time you see a particular gym in Explore, Trace asks that gym's website for the icon it publishes, and saves it on this phone. Nothing about you goes with that request: no name, no account, no location, no identifier, and no cookie survives it. The gym's web host can see that someone asked, and nothing more than that. Each gym is asked once, ever, and a gym whose site has no usable icon is never asked again.",
                    "That is the complete list. There is no analytics, no crash reporting, no advertising identifier, no tracking pixel, and no third party SDK that phones home."
                ]),
                Section(heading: "Filming other people", body: [
                    "A gym is full of people who did not agree to be in your video. Because Trace never uploads footage, filming in a busy gym does not put a stranger's image on anyone's server. It remains your responsibility to film in line with your gym's rules and the law where you are.",
                    "When more than one person is in frame, Trace measures the largest tracked body and ignores the rest. It does not recognize faces and cannot identify anyone."
                ]),
                Section(heading: "Children", body: [
                    "Trace is not directed at children under 13 and we do not knowingly create accounts for them. If you believe a child has made an account, write to us and we will delete it."
                ]),
                Section(heading: "Your control", body: [
                    "Delete any climb, route or gym at any time, from the item itself. Deleting removes the file from the phone.",
                    "Deleting your account, from Profile, removes every climb, clip, route, gym and body measurement from this phone and ends your session. Where an account record exists with our authentication provider, we delete it on request to the address below.",
                    "Signing out leaves everything on the phone exactly where it is. It is a sign out, not a wipe."
                ]),
                Section(heading: "Your rights", body: [
                    "If you are in the UK or EU, the UK GDPR and GDPR give you rights over personal data we hold. Since the only personal data we hold is your email address and the date your account was created, a request to see, correct or delete it is quick to answer. Write to hello@traceclimb.co.",
                    "If you are in California, the CCPA gives you similar rights. We do not sell or share personal information, and we never have."
                ]),
                Section(heading: "Changes", body: [
                    "This document ships inside the app, so it can only change when you install an update. The version number at the top changes with it, and a material change will be flagged in the app rather than made quietly.",
                    "Version 1.1 added gym logos, described above. It is the only thing that has ever been added to the list of what leaves this phone."
                ])
            ],
            insideApp: insideApp)
    }
}

// MARK: - Terms of Use

extension LegalScreen {
    static func terms(insideApp: Bool = true) -> LegalScreen {
        LegalScreen(
            title: "Terms of Use",
            updated: "24 September 2026",
            standfirst: "The agreement between you and Trace. It is short because the app does little on your behalf: it measures your own climbing on your own phone.",
            sections: [
                Section(heading: "What Trace is", body: [
                    "Trace records or imports a video of you climbing, estimates where your joints were in each frame, and reports measurements of how you moved. It also photographs a wall and picks out holds by color.",
                    "Trace is a measuring instrument and a training aid. It is not a coach, a physiotherapist, or a medical device, and nothing it says is medical advice."
                ]),
                Section(heading: "Climbing is dangerous", body: [
                    "You climb at your own risk. Trace cannot see the ground, your pads, your spotter, whether a hold is loose, or whether you are too tired to be on the wall. Never let a drill or a suggestion from this app override your own judgment, your gym's rules, or your partner's.",
                    "Do not use this app while you are on the wall. Set the phone down, climb, then look at it.",
                    "To the fullest extent the law allows, we are not liable for injury, loss or damage arising from your climbing or from your use of Trace."
                ]),
                Section(heading: "What the measurements are worth", body: [
                    "Every number Trace produces is an estimate from a single camera. It does not know how far away you were unless you tell it your height, and even then the scale is inferred rather than measured. Distances, speeds and energies are approximations, and the app says so where it shows them.",
                    "Trace compares your attempts against your own earlier attempts. It does not rank you against other climbers, and it deliberately never judges your choice of sequence: it measures how you moved, not which holds you chose.",
                    "When tracking is poor, Trace says so and declines to give feedback rather than guessing. Treat that refusal as the honest answer it is."
                ]),
                Section(heading: "Your account", body: [
                    "You need an account to use Trace. Keep your password to yourself; you are responsible for what happens under your account. Tell us if you think someone else has it.",
                    "One person per account. Do not share one."
                ]),
                Section(heading: "Trace Pro", body: [
                    "Your first route scan is free. Scanning further routes, and the recommendations built from them, require a Trace Pro subscription.",
                    "Trace Pro is sold through the App Store and billed to your Apple ID at the price shown before you confirm. It renews each period until you turn renewal off, which you do in Settings under your name, then Subscriptions. Turning it off at least 24 hours before the next renewal stops that charge.",
                    "Refunds are handled by Apple, not by us, under Apple's own policy.",
                    "If your subscription ends, everything you have already scanned and analyzed stays on your phone and stays readable. You simply cannot scan new routes until you subscribe again.",
                    "If the price changes, Apple will ask you to agree before charging the new amount."
                ]),
                Section(heading: "Your content is yours", body: [
                    "Your clips, photographs and measurements belong to you. We claim no license over them, which is easy for us to promise because we never receive them.",
                    "Do not record someone who has asked you not to, and do not use Trace to film anyone in a place where they would expect privacy."
                ]),
                Section(heading: "Fair use of the app", body: [
                    "Do not reverse engineer the app, work around the subscription, or use it to build a competing product. Do not use it for anything unlawful."
                ]),
                Section(heading: "No warranty", body: [
                    "Trace is provided as it is. We do not promise it will be accurate, uninterrupted, or fit for any particular purpose. Pose estimation fails in poor light, at distance, and when you face into the wall, and some clips will simply not track.",
                    "Where the law does not allow us to exclude liability, we do not attempt to."
                ]),
                Section(heading: "Ending it", body: [
                    "You can stop using Trace whenever you like, and delete your account from Profile. We may end an account that breaks these terms.",
                    "These terms are governed by the laws of the Commonwealth of Massachusetts, United States."
                ])
            ],
            insideApp: insideApp)
    }
}
