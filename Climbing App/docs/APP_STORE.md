# Submitting Trace

Everything on Apple's side, with the values to paste in. The app-side work is
done and committed; what is listed here needs an App Store Connect session and,
in two places, a decision.

Bundle identifier `co.traceclimb.app` · version 1.0 · iPhone only, portrait,
iOS 17 and up · team TA274AR6D5.

## Still open, and yours to decide

**1. Accounts.** The app ships in local-only mode: `AuthClient.isConfigured` is
false because `SUPABASE_URL` and `SUPABASE_ANON_KEY` are not set, so
`LocalStartScreen` asks for a name and goes straight in. That is a complete,
submittable product and it matches what the privacy policy promises. Turning
accounts on means provisioning a Supabase project, adding those two keys to the
build settings, and running `Supabase.sql` on it. Nothing else changes: the
sign-in and sign-up screens appear on their own.

**2. Screenshots.** `docs/screenshots/` holds four at 1320×2868, which is the
6.9" size Apple asks for, and they are the right four screens: home, a route,
the pose overlay, the efficiency card. They are **not submittable**, because the
climbs in them are the synthetic demo climber, a grey stick figure on a black
wall. They are there to say which screens to shoot. Real ones need your own
footage of your own climbing, recorded in the app.

**3. Never run on a physical iPhone.** The camera, the 60fps capture path, and
Vision pose tracking on a live buffer have never executed on hardware, only in
the Simulator, which has no camera. App Review runs on devices.

## The app record

| Field | Value |
|---|---|
| Name | Trace |
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

The free tier is one route scan. Everything already recorded stays readable
after a subscription ends, which the Terms say and the app does.

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
> Scanning a route is limited to one scan without a subscription. Trace Pro is a
> StoreKit subscription, monthly or yearly, and Restore a purchase is on the
> same screen.
>
> Nothing is uploaded. There is no server holding user content.

## Before hitting submit

- [ ] Run on a physical iPhone, film a real climb, check the analysis
- [ ] Decide accounts: local-only, or provision Supabase and run `Supabase.sql`
- [ ] Host `docs/privacy.html` and `docs/terms.html`, paste the privacy URL
- [ ] Shoot real screenshots at 1320×2868
- [ ] Create both subscriptions at the prices above, with review screenshots
- [ ] Archive, upload, confirm no ITMS-91053 (the privacy manifest should hold)
