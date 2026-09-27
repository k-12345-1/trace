# Submitting Trace

Everything on Apple's side, with the values to paste in. The app-side work is
done and committed; what is listed here needs an App Store Connect session and,
in two places, a decision.

Bundle identifier `co.traceclimb.app` · version 1.0 · iPhone only, portrait,
iOS 17 and up · team TA274AR6D5.

**The record exists.** Apple ID **6816587121**, created under Lineage Health,
Inc., which is the name the App Store will show as the seller. The identifier
`co.traceclimb.app` is registered; before this the app had only ever been signed
with the team's wildcard profile, which is why it ran on a phone without ever
having a bundle ID of its own.

Listed as **Trace Climbing**, subtitle "See how you climb". Plain "Trace" is
taken on the App Store and Apple offers only a trademark claim against it. It
changes nothing on the phone: the home screen name comes from
`CFBundleDisplayName`, which is and stays "Trace".

Filled in already: name, subtitle, categories, description, promotional text,
keywords, copyright, the App Review notes, pricing, availability, the age
rating and the App Privacy answers.

**Pricing** is free in all 175 countries, with the subscriptions carrying the
revenue. **Age rating** came out 4+ worldwide, every content category answered
None. **App Privacy** declares one data type, Email Address, linked to identity,
used for App Functionality, not used for tracking, which is exactly what
`PrivacyInfo.xcprivacy` says. It cannot be published until there is a privacy
policy URL to go with it.

Two answers in there were judgement rather than fact, and are worth a second
opinion:

- **Health or Wellness Topics: No.** Trace gives training feedback on climbing
  movement, not self-care or lifestyle advice, and it provides no medical or
  treatment information. Answering yes would raise the rating for no good
  reason, but it is a line somebody could draw differently.
- **Fitness data: not collected.** True under Apple's definition, which is about
  data leaving the device. Every measurement Trace makes stays on the phone.

**Content Rights is deliberately unanswered.** The question asks whether the app
accesses third-party content *and whether you hold the necessary rights*. Trace
fetches gym logos from gym websites, so "no" is untrue, and "yes, I have the
rights" is a legal claim that is not mine to make. Either answer it knowingly or
drop the logo fetching, which is one file, `LogoFetcher`.

## Still open

**1. Accounts: on.** Project `uksqwnfmqytwftpttbdk`, free tier, us-east-1, in
its own organization. `Supabase.sql` is installed, the publishable key is in
`SupabaseConfig`, and the sign-in and sign-up screens are live in place of the
local start screen. Verified against the project: the key authenticates where a
wrong one gets a 401, email sign-up is enabled, and `delete_current_user` exists
and refuses an unauthenticated caller rather than 404ing.

**One thing to settle before launch: email delivery.** The project requires
email confirmation, so every sign-up waits on a message. Supabase's built-in
SMTP is for development and rate-limits to a handful an hour, which on a launch
day means climbers who never receive the link and never get in. Either connect a
real sender (Resend, Postmark, SES) under Authentication, Emails, SMTP, or turn
confirmation off and accept unverified addresses. The first is the right answer
and takes about ten minutes.

**2. Screenshots.** `docs/screenshots/` holds four at 1320×2868, the 6.9" size
Apple asks for, of the right four screens: home, a route, the pose overlay, the
efficiency card. They are **not submittable**, because the climbs in them are
the synthetic demo climber. Trace now runs on a phone, so the real set is a gym
session away: film a boulder, let it analyze, and screenshot those same four
screens.

**3. Running on a phone: done.** Tracking reads 90% on real gym footage from a
real iPhone. This was the last unknown in the app itself. The Simulator still
reports 0%, which is a Simulator limitation and is pinned by a known-issue test.

## The app record

| Field | Value |
|---|---|
| Name | Trace Climbing (plain "Trace" is taken) |
| Subtitle | See how you climb |
| Category | Health & Fitness (secondary: Sports) |
| Age rating | 4+ |
| Privacy policy URL | wherever `docs/privacy.html` is hosted |
| Support URL | a page that reaches hello@traceclimb.co |
| Copyright | 2026 Trace |

### Description

> Trace watches your climbing and tells you where the effort went.
>
> Film a boulder on your phone. Trace finds your body in the footage, follows
> your centre of mass up the wall, and measures the movement: how directly you
> got from each position to the next, how much height you gained twice, how long
> you hung about, how straight your arms were when you were not moving. It gives
> you a grade you can argue with, because every part of it is named and shown.
>
> Scan a wall and Trace reads the holds, so a route you are working becomes a
> thing you can keep attempts against and watch change.
>
> All of it happens on your phone. Your clips are never uploaded. There is no
> account to make, no server holding your climbing, and nothing about you leaves
> the device.

### Keywords

`climbing,bouldering,technique,movement,coach,training,route,beta,gym,analysis`

### What's New (1.0)

> First release.

## Subscriptions

One group, **Trace Pro**, two durations, same features either way. Reference
names and IDs must match `Trace.storekit` exactly or the products will not load.

| Product ID | Reference name | Duration | Price |
|---|---|---|---|
| `co.traceclimb.pro.monthly` | Trace Pro Monthly | 1 month | $4.99 |
| `co.traceclimb.pro.yearly` | Trace Pro Yearly | 1 year | $30.00 |

Display names "Trace Pro, monthly" and "Trace Pro, yearly"; descriptions are in
`Trace.storekit`. Each product needs a review screenshot of the paywall. The
group needs a display name: **Trace Pro**.

The free tier is three goes, spent on anything that gives feedback: a climb
recorded, a clip imported, or a wall scanned. Everything already recorded stays
readable after a subscription ends, which the Terms say and the app does.

## App Privacy answers

These must match `PrivacyInfo.xcprivacy` and `docs/privacy.html`.

- **Data used to track you:** none.
- **Data linked to you:** Email address, and only when accounts are switched on.
  Purpose: App Functionality.
- **Data not linked to you:** none.
- **Collected but not sent:** everything else. Video, pose, measurements,
  routes, gyms, height, reach and weight stay on the device, which Apple's
  questionnaire does not count as collection.

Three things do leave the phone, all named in the policy: the account (only if
switched on), the purchase (Apple's, not ours), a gym's logo fetched once from
that gym's own website, and the letters typed into the place field, which go to
Apple Maps for completions.

## Review notes

> Trace needs no account. The first screen asks for a name and goes straight in.
>
> The app measures climbing from video. To see it work without a wall, use
> Import a clip on the Add screen and choose any video of a person moving; the
> analysis runs on the device and takes a few seconds per minute of footage.
>
> The first three clips or scans are free; the fourth opens the paywall. Trace
> Pro is a StoreKit subscription, monthly or yearly, and Restore a purchase is
> on the same screen.
>
> Nothing is uploaded. There is no server holding user content.

## Before hitting submit

- [x] Run on a physical iPhone, film a real climb, check the analysis
- [x] Create the Supabase project, run `Supabase.sql`, add the two keys
- [x] Register the bundle ID and create the app record
- [ ] Accept the updated Developer Program License Agreement (Account Holder only)
- [ ] Somewhere to host the privacy policy, and a support page. traceclimb.co
      does not resolve, and the legal documents give hello@traceclimb.co as the
      contact address, so that domain needs registering or the address changing
- [x] Age rating, pricing and availability, App Privacy answers
- [ ] Answer Content Rights, or drop the gym logo fetching
- [ ] Publish the App Privacy answers once the policy URL exists
- [ ] The two subscriptions in App Store Connect
- [ ] Connect real SMTP, or turn off email confirmation
- [ ] Host `docs/privacy.html` and `docs/terms.html`, paste the privacy URL
- [ ] Shoot real screenshots at 1320×2868
- [ ] Create both subscriptions at the prices above, with review screenshots
- [ ] Archive, upload, confirm no ITMS-91053 (the privacy manifest should hold)
