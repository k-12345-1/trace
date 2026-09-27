# What Trace can say about climbing, and what it cannot yet

A map from the coaching vocabulary to the measurements, written because the
coaching arrived faster than the analysis and the gap needed naming rather than
apologising for. Every row says which engine already does it, what work it needs,
or why one camera and a skeleton cannot do it at all.

## The two facts that decide everything below

**1. Trace sees fifteen joints and no holds.** Vision gives nose, neck,
shoulders, elbows, wrists, hips, knees, ankles, root. There is no toe, no heel,
no hand orientation, no finger. `RouteScanner` finds holds, but it finds them in
a *photograph of a wall*, and nothing has ever connected a hold to a limb. So the
app currently knows where a body went and never what it was holding.

**2. It is one camera, so there is no depth.** Every measurement is a projection
onto the image plane. "Hips close to the wall" is a distance along the axis the
camera cannot see. Some of it can be recovered indirectly (a turned pelvis
foreshortens, which is what `ReachEngine.hipOpenness` reads) but the raw quantity
is not available and no amount of care makes it so.

Almost every gap below is one of those two.

---

## Movement

| What | Status | How |
|---|---|---|
| **Movement efficiency** | **Built** | `EfficiencyEngine`: round trips, re-lifting, travel between moves, time not moving. `MoveEngine` measures directness position to position. |
| **Centre of mass** | **Built** | `CenterOfMass` from segment masses; `BodyScale.lift` for height gained and regained. |
| **Balance** | **Partly built** | `MetricsEngine.plantedBase` now puts the base of support under the feet that are actually on something. What is measured is the sideways offset of the COM from that base. |
| **Footwork: precision** | **Built** | `MetricsEngine.footAdjustmentTimes`: a foot placed and then replaced. |
| **Footwork: height** | **Measurable now** | Ankle against hip height, in torso lengths. On the real climb feet ran from 1.38 below the hips to 0.32 above. This is the "unnecessarily high foot" reading. |
| **Body positioning: twist** | **Measurable now** | `ReachEngine.hipOpenness`, self-calibrated against the climber's own squarest frame. |
| **Body positioning: support triangle** | **Measurable now** | Contact points as a polygon; area, and whether the COM projects inside it. Measured 0.20 to 2.54 torso² across one climb's reaches, COM inside at four of six. |
| **Momentum** | **Partly built** | `MetricsEngine.deadpointOffsets` times the catch against the apex of the arc. Now that a throw is one event instead of six it is worth trusting; it was averaging phantom events. |
| **Legs before arms** | **Measurable now** | Foot placements against hand launches. Tested: 3 of 10 reaches had a foot move within two seconds, and the difference in body-led share was 68% against 64%. No effect on one climb, which is a result rather than a feature. |
| **Overextension** | **Needs a definition** | Reaching with the arm while the feet stay put is the sequencing measure above. Reaching *past* what the body can support needs the hold position. |
| **Hips over the foot** | **Not measurable** | The useful version is hips over the foot *and towards the wall*. The second axis is depth. |

## Technique

| What | Status | How |
|---|---|---|
| **Straight arms** | **Built** | `staticElbowAngle`, and `ReachEngine.catchElbow` per reach. |
| **Lock-offs** | **Buildable, no holds needed** | One elbow held bent and near-still while the other hand is thrown. Both series already exist. |
| **Flagging** | **Buildable, no holds needed** | Exactly one foot planted while the other leg is extended and still. `plantedBase` already says which feet are on. A flag is a deliberately unsupported leg, which is the one leg position that needs no hold to identify. |
| **Drop knees** | **Partly measurable, ambiguous** | Hips narrow and the knee turns in. Measured on real footage: hips at 0.31 to 0.50 of square through a section, thighs at 50° to 90° off vertical. The problem is that a **high step** looks the same in two dimensions, and telling somebody to drop a knee when they already have is worse than silence. |
| **Active feet** | **Needs holds** | Whether the foot is being pushed through, rather than resting, is force. The closest proxy is the COM rising while the ankle stays put. |
| **Smearing** | **Needs holds** | Smearing is a foot on *no hold*. Requires knowing where the holds are. |
| **Heel and toe hooks** | **Not measurable** | Vision reports an ankle. There is no heel and no toe, so the thing that distinguishes these cannot be seen. A different pose model would be needed. |
| **Knee bars** | **Not measurable** | Needs the hold geometry the knee is locked against, and depth. |
| **Opposition** | **Not measurable directly** | Pushing two ways at once is a force pattern. Visible only as an inference: contacts wide apart and stable with the COM between them. |

## Problem solving

| What | Status | How |
|---|---|---|
| **Hesitation** | **Built** | Long stops read as reading the route while hanging on it. |
| **Reading the route** | **Needs holds** | What to praise or fault is the sequence chosen against the sequence available. The second half does not exist yet. |
| **Correct sequencing** | **Needs holds** | Same. Also needs hold-to-limb association over time, which is a tracking problem on top of a detection one. |
| **Technique selection** | **Needs holds** | "You could have drop-kneed off that foot" requires knowing the foot was on a hold that allows it. |

---

## The one piece of work that unlocks the most

**Associate holds with limbs.** `RouteScanner` finds holds in a wall photograph.
`PoseTracker` finds wrists and ankles in a video. Nothing joins them, and that
join is the precondition for smearing, route reading, sequencing, technique
selection, hold orientation against pull direction, and a real version of
overextension. It is most of the "Problem solving" column and a third of
"Technique".

It is not small. It needs the scan and the clip to share a frame of reference
(the wall photograph and the video are different images of the same wall), a
per-frame nearest-hold association with hysteresis so a hand does not flicker
between two holds, and a way to fail honestly when the wall in the clip is not
the wall that was scanned.

## The physics worth attaching, and to what

- **Base of support.** A body is stable while the COM projects inside the
  contacts. Measurable now, per frame, and the one principle that covers the
  pyramid drawings directly.
- **Moment arms.** Torque on a shoulder is force times the perpendicular
  distance from the joint to the line of pull, which is why a straight arm is
  cheap and a bent one is not. The elbow angle is a direct proxy and is already
  measured.
- **Impulse at the deadpoint.** At the top of the arc vertical velocity is zero,
  so the hand needs least force to hold. Measured as timing error in
  milliseconds. Real physics, already there.
- **Work against gravity.** mgh, with height in torso lengths and mass optional.
  Height gained twice is work paid twice. Already measured and, as of today,
  measured correctly.
- **Friction cone.** Whether a foot holds depends on the angle between the force
  and the hold's normal. Needs holds, and needs their orientation, which the
  scanner does not currently estimate.
- **Rotational equilibrium.** A barn door is a body rotating about the line
  through two contacts. Detectable in principle from the contacts and the COM,
  and the most promising unbuilt physics measure that needs no depth.

## Order I would build in

1. **Flagging and lock-offs.** No holds, no depth, both are pure pose geometry,
   and both are named technique a climber recognises.
2. **The support-triangle reading**, with Katie's labels on which shapes are the
   bad ones. The measurement exists; the verdict does not.
3. **Barn-door / rotational equilibrium**, which is real physics on contacts
   Trace already has.
4. **Holds to limbs**, which is the big one, and unlocks the whole third column.

---

# Audit: is what Trace recommends correct?

Prompted by the first labelled clip. Katie sent a thirty-second ascent back with
a verdict: *"an example of good climbing as the arms are straight, footwork is
precise, hips are close to the wall, weight is distributed well"*, plus good
force on the final dynamic move. Trace disagreed with all four. Each is examined
below on its merits rather than assumed wrong because an expert said so, and
they come out differently.

### 1. "Weight hanging off your arms" — measuring the wrong thing

`comOffsetFromFeet` is the **horizontal** distance in the image between the
centre of mass and the base of support. Its own comment says it reads as hips
hanging off the wall *when filmed side on*. The Record screen tells people to
put the phone **square to the wall**. Filmed square, the same number reads as a
body spread sideways, which is a stem or a flag, not weight on the arms.

On this clip it measures 1.40 torso lengths and the climber is stemming wide.
The finding fires above 0.35 and calls anything above 0.90 "dominant", so a
perfectly balanced wide position is reported as the worst thing in the climb.

**This one is wrong by construction on the footage Trace asks for.** The fix is
a product decision: suppress it on square-on capture, or change what it claims.

### 2. "Imprecise feet" — right idea, wrong denominator *(fixed)*

It fired on a raw count: three repositions, whatever the climb. A three-move
boulder and a thirty-move route were judged identically, so a longer climb was
faulted for being longer. Eleven resets across nine hand moves is 1.2 a move;
eleven across three moves would be 3.7. The old rule called them the same.

Now counted per hand move, and per fifteen seconds when the moves cannot be
read. The thresholds are set where the old ones sat for a five-move boulder, so
a climb of that shape reads exactly as before and only the scaling changes.

### 3. "Bent arms while static" — was measuring nobody's arm *(fixed)*

Two defects, both real. Seven percent of the still-frame readings were below 35
degrees, which is past the anatomical limit: the tracker had folded a wrist back
to its own shoulder. And the readings were averaged across both arms, giving 101
degrees on a set that is a quarter below 51 and a quarter above 145, because one
arm hangs while the other reaches. The mean is a position nobody was in.

The weight-bearing arm is measured now, which is what the coaching is about, and
it reads 115 degrees. **The disagreement with the label survives the fix**: an
expert calls this climb straight-armed and the rubric treats 115 as as bad as it
gets. One labelled clip cannot move a threshold, so a test holds both numbers
and fails if the rubric is ever recalibrated.

### 4. "Catching outside the deadpoint" — unverified

456 milliseconds off the apex on a move Katie says generates good force. The
detector now finds nine hand moves instead of thirty-six, so the number is at
least computed over real events, but every contact is matched to the nearest
apex of the **centre of mass** whether or not the move was dynamic. On a climb
that is mostly static that produces a number from nothing. Needs a test for
whether a move was dynamic at all before its timing is judged.

### What this changes about how thresholds get set

Three of four findings on the one clip with a verdict attached were wrong, and
two were wrong in ways no amount of internal consistency would have caught: a
measure that means something different under the capture the app itself asks
for, and a count that punished length. Neither is a calibration error. Both were
found by holding a number against somebody who knows what good climbing looks
like.

The remaining disagreements are calibration, and calibration needs more than one
labelled example. Until there are several, the honest position is that the
thresholds are unvalidated, and this document says so rather than the app
implying otherwise.

---

# Open: every distance is measured in anisotropic units

Found while fixing "weight hanging off your arms", and larger than that finding.

Vision normalizes each axis to 0...1 **independently of the other**. On the real
clip, 1206 by 2622, one unit of x is 1206 pixels and one unit of y is 2622. So a
horizontal distance and a vertical one are not the same kind of number, and:

- a sideways offset divided by the mostly-vertical torso was overstated by the
  aspect ratio, **2.17 times** on that clip
- `hypot(dx, dy)` mixes the two, so **a path's length depends on its direction**

That reaches path length, entropy, jerk, round trips, move waste, reach travel
and hold geometry. Correcting it on the fixture moved entropy from 1.25 to 1.09
and move waste from 27% to 33%.

The resting-weight finding is now immune, because it compares a horizontal
distance against a horizontal body scale and the anisotropy cancels exactly. The
rest are not.

**Why it is not fixed here.** The honest fix is to scale x by the frame's aspect
at the point the joints are made, which changes the meaning of every stored
climb. Old climbs would need correcting on read, from the aspect of a video file
that is still on disk, and the overlay maps joints to the screen assuming the
current convention. That is a coherent change and not a late-evening one.

It also does not invalidate the comparisons the app actually makes. Every
readout is against the same climber's own earlier climbs, and a library filmed
on one phone in one orientation carries one aspect ratio throughout, so the
error is a constant factor that cancels. It bites when clips of different shapes
are compared, and whenever a number is read as a physical length, which is
exactly what "1.42 torso lengths to the side of your feet" invited.
