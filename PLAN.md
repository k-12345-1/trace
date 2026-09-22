# Spotter

Working plan, v0.3 (2026-09-22).

The app is called **Spotter**. In bouldering your spotter is the person who watches you climb, which is exactly what this is.

v0.2 cut route scanning, gym route databases, ticklists, route recommendations and the social feed. v0.3 records what has actually been built.

## Build status

Phases 1 through 4 are implemented and compiling. Source in `Spotter/`, native SwiftUI, iOS 17+, 16 files. All six planned leaks are now wired end to end.

| Piece | State |
|---|---|
| Guided capture, framing guide, 60fps where available | Built |
| Import an existing clip from Photos | Built |
| Vision body-pose tracking over a recorded clip | Built |
| Centre of mass, Dempster segment fractions | Built, unit-checked |
| Geometric entropy, convex hull, log dimensionless jerk | Built, unit-checked |
| Static elbow angle, pauses, foot re-placements, path ratio | Built, unit-checked |
| Weight on arms: COM offset from feet, in torso lengths | Built, unit-checked |
| Deadpoint timing: hand contact against the COM apex | Built, unit-checked |
| Finding engine with severity ranking and drills | Built |
| Confidence gate, says nothing below 55% tracking | Built |
| Playback with skeleton and COM overlay | Built |
| Local-only storage, no accounts, no network | Built |
| Attempt-over-attempt comparison by typed label | Built |
| Focus that persists across sessions (Phase 2) | Built, unit-checked |
| Entropy trend and movement signature (Phase 2) | Built |
| Beta clustering by COM path shape (Phase 3) | Built, unit-checked |
| Drill library and assignment (Phase 4) | Built |
| Delete a climb | Built |

Fifty-four known-answer checks pass against the shipping maths: entropy is 0.0000 for a straight path and 0.685 for a circle (theory says ln 2 = 0.693), a right angle measures 90.000 degrees, the convex hull of a noisy square returns exactly 4 vertices, and a sparse skeleton correctly returns no centre of mass rather than a bad guess. On the clustering: an identical path that has been moved and rescaled scores 0.0000, the same path with tracking noise 0.0072, and a genuinely different sequence 0.4473, against a 0.35 threshold. On the focus: it refuses to pick one from a single climb, retires itself when the target is met, and stays open on small gains. On the two newest metrics: a climber stacked over their feet measures 0.00 torso lengths of offset and one hanging out measures exactly 0.50; a single upward throw yields exactly one apex and one hand contact, timed to within 0.02s of each other; and a purely static climb reports no dynamic moves at all rather than claiming perfect timing.

Metrics now decode leniently, so adding a measurement in future will not throw away a climber's stored history.

**The one number picked by judgement rather than derived** is `BetaClustering.sameSequenceThreshold = 0.35`. The synthetic margins around it are wide, but real tracking noise will be far worse than synthetic noise, so this wants calibrating against Phase 0 footage before it is trusted.

**What is still unverified: everything that depends on real footage.** The maths is right. Whether Vision can track a body pressed against a wall, facing away, with a heel hooked overhead, is unknown and is still the question the project lives or dies on.

---

## 1. The product in one paragraph

You put your phone on the floor and climb. Between burns you pick it up and it tells you **one** thing, in a sentence, with the moment highlighted on your own video. It remembers what it told you. Over a session it checks whether you did it. Over a month it shows you that your movement actually changed. It never tells you what holds to use.

---

## 2. The governing constraint: beta-agnosticism

Every climber's beta is different, and a good beta for a tall climber is a bad beta for a short one. So the app must never evaluate *sequence choice*. It evaluates **execution quality**, which is measurable without knowing anything about the wall, the holds, the grade, or the route.

This is a constraint, and it is also a gift. It means:

- No hold detection. No route database. No gym partnerships required to function.
- No computer vision beyond a human skeleton.
- Works at any gym, outdoors, on any wall, from day one, with zero cold-start.
- Nothing to scrape, so no setter-IP or gym-goodwill problem.

Two rules fall out of it, and they should be enforced in code:

1. **Never name a hold or prescribe a sequence.** Not "use the left crimp." Only "you pulled through this move with bent arms."
2. **Compare a climber only against themselves.** Against their previous attempts on the same route, and against their own trend over weeks. Never against other users, and never against an absolute standard.

Rule 2 has a subtlety that turns into the best feature in the app, see §4.2.

---

## 3. What gets measured

All of it is arithmetic on a joint time series. No ML beyond the pose model itself.

### 3.1 Whole-climb quality

**Geometric entropy of the center-of-mass path.** `H = ln(2L / C)`, where `L` is the length of the COM path and `C` is the perimeter of its convex hull. The established climbing-specific efficiency measure: it falls as a climber learns a route and correlates with lower measured energy expenditure. This is the headline score.

**Normalized jerk of the COM trajectory.** Dimensionless third-derivative measure of fluency. High jerk is start-stop-lurch climbing, and the forearms pay for it.

**Path efficiency ratio.** COM path length over straight-line distance. Intuitive, and explains "you wandered" in one number.

### 3.2 The coachable leaks

These are what actually become sentences.

| Leak | Measured as | What it means |
|---|---|---|
| Bent arms at rest | Mean elbow angle during low-COM-velocity windows | Biceps holding what the skeleton should hold. The most common and most expensive beginner leak. |
| Weight on arms, not feet | Horizontal COM offset from the midpoint of the feet | Either poor hip positioning or fighting a barn-door |
| Lurchy movement | Per-move jerk and COM velocity profile | Static strength substituting for momentum, or momentum substituting for control |
| Mistimed dynamic moves | Offset between COM vertical-velocity zero-crossing and hand contact | Catching before or after the apex means pulling your own bodyweight for no reason |
| Imprecise feet | Count of foot re-placements (land, shift, land again) | Not looking at your feet |
| Hesitation | Pause count, duration, and where they fall | Reading the route while hanging on it instead of from the ground |

### 3.3 The movement signature

Every leak above, tracked per climb, then aggregated by terrain steepness (inferred from the climber's average body angle, not from the wall) and over time. This is the memory that makes it a partner rather than a calculator.

---

## 4. What makes it a training partner and not a scorecard

### 4.1 One thing at a time

After a climb it says **one sentence**. Not six metrics, not a dashboard. Findings get ranked by estimated energy cost, gated by tracking confidence, and the top one is the only one shown. Tap to see the rest if you want them.

It also keeps that focus. A partner who gives you a different thing to work on every burn is useless. The focus metric persists across the session and across sessions until it measurably improves.

### 4.2 Your betas, compared against each other

When you try the same route three times, the app clusters the attempts by **COM path shape similarity**. Similar paths mean you tried the same sequence. A dissimilar path means you tried a different one.

That gives two distinct and genuinely useful outputs, neither of which requires knowing a single hold:

- **Same beta, repeated:** did entropy and jerk drop? This is learning, quantified. If attempt 3 is not smoother than attempt 1, you are not refining, you are just getting tired.
- **Different betas tried:** "your second sequence cost you noticeably less than the other two." The app never suggests a beta. It tells you which of *your own* solutions was cheapest, and you decide what that means.

This is the feature I would build the demo around. It respects the beta point exactly, and no other app does it.

### 4.3 Drills, not just diagnoses

Every leak maps to a drill. A diagnosis with no prescription is a complaint.

| Leak | Drill |
|---|---|
| Bent arms | Straight-arm traverse. Climb an easy traverse with elbows never below ~150 degrees. |
| Weight on arms | Hip-turn and flagging drill on easy terrain, focusing on turning a hip to the wall before each reach. |
| Imprecise feet | Silent feet. Place each foot once, with no noise and no adjusting. |
| Lurchy movement | Downclimb everything you climb. Forces control and doubles your volume. |
| Mistimed dynamics | Deadpoint isolation. One move, repeated, catching at the apex. |
| Hesitation | Read from the ground, then climb without stopping. No re-reading on the wall. |

### 4.4 The session arc

- **Opening:** "Last session we worked on straight arms on steep terrain. Let's check it."
- **Between burns:** one sentence plus your clip with the skeleton and COM path overlaid.
- **Closing:** did the focus metric move today? If yes, celebrate and pick the next focus. If no, keep the focus and change the drill.

### 4.5 Tone

A good partner is specific, brief, and not a cheerleader. "Your elbows were bent for 4 seconds before the move at 0:12" is useful. "Great effort, keep crushing!" is noise. Findings cite a timestamp and point at the video, always.

---

## 5. Technical architecture

- **App:** native SwiftUI, iOS 17+. Camera and on-device ML are the product, so it has to be native.
- **Capture:** AVFoundation, 1080p60 preferred. 60fps matters for jerk and deadpoint timing. 30fps fallback with degraded confidence on those two metrics.
- **Pose:** Apple Vision `VNDetectHumanBodyPoseRequest` (19 joints, 2D, real-time, on-device, free). MediaPipe BlazePose (33 landmarks, better feet) evaluated as the alternative in Phase 0. Foot landmark quality likely decides it.
- **Analysis:** pure Swift on the joint time series. Runs post-capture rather than live, to avoid thermal throttling during recording.
- **Coaching text:** findings are computed on-device as structured data, then an LLM call turns the top finding into a sentence. Tiny payload. Falls back to templated text offline.
- **Storage:** **entirely on-device for v1.** SwiftData plus video in the app container. No accounts, no backend, no Supabase, no upload.

That last point is a significant simplification from v0.1 and it follows directly from cutting the social feature. With nothing to share, there is nothing to sync, and the entire privacy surface in a gym full of other people's faces collapses to zero. Add an account layer later only if multi-device sync is actually wanted.

### 5.1 The hard problems

These are the reasons this might not work, and Phase 0 exists to test them.

1. **Occlusion.** A body pressed to a wall, facing away, heel hooked overhead, is close to the worst case for models trained on upright unoccluded people. Expect joint dropouts and left/right limb flips.
2. **Scale in frame.** A climber at the top of a long route is a few hundred pixels tall and pose confidence collapses. **Bouldering only for v1.** 4m with the phone on the floor is tractable; 15m of lead is not.
3. **Camera geometry.** Every §3.2 metric depends on a known viewing angle. Solution: a guided capture flow that tells the user where to put the phone, checks framing before recording, and refuses bad setups. Constraining capture is a feature, because it makes every number downstream trustworthy.
4. **COM from 2D** is accurate enough for relative comparison, not for absolute claims. Since §2 rule 2 makes everything relative anyway, this is fine. It just must never be presented as an absolute score.
5. **Multiple people in frame.** Gyms are crowded. Needs climber selection: most central and largest, with a tap to correct.

### 5.2 Confidence gating

Every analysis carries a tracking confidence and a capture quality score. Below threshold, the app says "I could not see that one clearly" and shows nothing. **Confidently wrong coaching is the product-killing failure mode.** Better to stay quiet.

---

## 6. Data model

Local only.

```
climbs        id, recorded_at, video_uri, duration, grade?, terrain_angle_est,
              pose_confidence, capture_quality, route_label?   // free text, user-typed, optional
poses         climb_id, frame_ts, joints[19]{x, y, conf}        // binary blob, not rows
analyses      climb_id, entropy, norm_jerk, path_ratio, com_offset_mean,
              static_elbow_mean, foot_replacements, pause_count, pause_total_s,
              deadpoint_offsets[], com_path[]
findings      id, climb_id, kind, severity, confidence, t_start, t_end, message
beta_clusters climb_ids[], similarity, cheapest_climb_id        // §4.2
focus         kind, started_at, baseline_value, current_value, resolved_at?
drill_log     focus_kind, drill_id, session_date, completed
```

`route_label` is a free-text string the user types if they want ("blue slab by the fan"). It exists only to group attempts for §4.2. It is never validated against anything.

---

## 7. Build order

### Phase 0: Feasibility spike. Go / no-go. **Still the next step.**

Spotter itself is now the harness: import 20 clips and read the tracking percentages.

1. Film 15 to 20 real boulders at your gym. Vary deliberately: slab, vertical, steep overhang, facing away, crowded background, mixed lighting.
2. Run Vision and MediaPipe over all of it offline.
3. Measure: per-joint detection rate, dropout length distribution, left/right flip rate, degradation with distance.
4. Compute entropy and jerk on the clips that track cleanly, and check the two things that must be true: a climber's third lap scores better than their first, and a strong climber scores better than a weak one on the same problem.
5. Test §4.2 specifically: do repeated attempts on one problem cluster by path shape, and do genuinely different sequences separate?

**Gate:** if the COM path does not match what a human sees, stop and redesign. Fallbacks: require a tripod, restrict to slab and vertical, or fall back to hand-contact-event analysis that needs no full skeleton.

Deliverable: a findings doc with numbers and annotated stills.

### Phase 1: One climb, one sentence. BUILT.

Guided capture with framing check, record, analyze, results screen: your video with skeleton and COM path overlaid, one finding, timestamped, tappable. Nothing else.

**Success test:** five climbers at your gym. Do they agree with the feedback? Do they record a second climb unprompted?

### Phase 2: Memory. BUILT.

Climb history, the focus mechanic (§4.1), the session arc (§4.4), movement signature trends over time.

### Phase 3: Your betas compared. BUILT.

Path-shape clustering, attempt-over-attempt comparison, cheapest-sequence identification. The demo feature.

### Phase 4: Drills. BUILT.

Drill library, drill assignment from focus, did-it-work checking.

All of v1 is now built. The kill gate at Phase 0 has still not been run.

---

## 8. Open questions

1. **Which gym, and can you film there?** Phase 0 is blocked without one place you can film freely and put the app in front of regulars.
2. **What does the reel argue?** Still cannot see it, Instagram requires login. Tell me the principles and I will map them into §3.2 or add metrics.
3. **Bouldering only, confirmed?** I have assumed yes throughout. Ropes are a v2 question at best.
4. **Solo build?** This version has no backend, so it is a single-person iOS project. Christian's infra skills are not needed until sync exists.
5. **Does it need a grade field at all?** I have left it optional. The app has opinions about movement, not about difficulty, and leaving grade out entirely is a defensible stance worth considering.

---

## 9. Risks

- **Confidently wrong feedback.** The main one. Mitigated by §5.2 confidence gating and by saying nothing when unsure.
- **Filming other people.** Much smaller now that nothing leaves the device, but the in-app norm still matters and some gyms have filming policies. Ask before Phase 0.
- **Battery and thermals.** Analyze post-capture, not live.
- **Liability.** It suggests physical activity. Disclaimer required, nothing framed as medical or injury advice.
- **Pose estimation simply not being good enough for climbing.** This is the real risk, which is why the whole plan is arranged so we find out in two weeks for almost no cost.

---

## 10. Next step

Phase 0, unchanged. Film twenty boulders, import them, and look at the tracking percentages before trusting a single number the app prints.
