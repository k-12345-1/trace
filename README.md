# Trace

*Listed on the App Store as Trace Climbing, because the bare name is taken there
by unrelated apps. The home screen reads Trace.*

An iOS training partner for bouldering. Point your phone at yourself, climb, and it
tells you one thing you could do better, with the moment highlighted on your own video.

Trace measures how well you executed the sequence you chose, not which sequence you
chose, so it needs no route database and no gym partnership: it works anywhere, from
the first climb. It can also photograph a wall, read the routes off it by colour, and
draw one shape through the line you pick, sized to the wall and standing the way
climbers on film stand.

## Running it

```bash
open "Climbing App/Climbing App.xcodeproj"
```

Pick the **Climbing App** scheme, then cmd-R to run or cmd-U to test. Run on a
device for the camera: the simulator has no real one, so use **Import a clip**
and **Choose from library** there.

From the command line:

```bash
xcodebuild test -project "Climbing App/Climbing App.xcodeproj" -scheme "Climbing App" \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

497 tests in 109 suites. Most are known-answer, every expected value coming from the
geometry or the colour maths; the rest run the engines over six photographed walls
and five tracked climbs kept as fixtures.

## Signing in

Trace asks for an account. Until the server issues them, a demo pair signs in locally
with no request made: email `trace@climb.co`, password `ClimbOn!`. In debug builds
only.

## What it measures

Everything is arithmetic on a joint time series produced by Apple's Vision body-pose
model. No machine learning beyond the pose model itself, and nothing leaves the phone.

| Metric | What it is |
|---|---|
| Geometric entropy | `ln(2L / C)` over the centre-of-mass path and its convex hull. The established climbing-specific efficiency measure. Lower is smoother. |
| Log dimensionless jerk | Third derivative of COM position, normalised by duration and path length. Lower is more continuous. |
| Path ratio | COM path length over straight-line distance. |
| Static elbow angle | Mean elbow angle while the COM is near-still. Bent arms at rest is the most expensive common leak. |
| Weight on arms | How far the COM sits sideways of the feet, in torso lengths, while resting. |
| Deadpoint timing | Gap between a hand arriving on a new hold and the apex of the COM arc. |
| Pauses and foot resets | Hesitation, and placements that had to be corrected. |

Route scanning is separate from all of that. Photograph a wall, tap one hold, and
every blob within a CIE Lab colour distance of it is picked out; the grade is read
off the route tag with Vision text recognition. No trained model and no route
database, so it works on the first photo in any gym. It cannot tell a route apart
from unrelated holds of the same colour, which is why you drop the wrong ones
before saving.

Below 55 percent tracking confidence Trace draws nothing and says nothing.
Confidently wrong coaching is the failure mode that kills this product.

## Layout

```
Climbing App/
  Climbing App.xcodeproj
  Climbing App/
    Analysis/    pose tracking, metrics, findings, focus, clustering, route scanner
    Models/      climb, pose, focus, gym, route
    Capture/     AVFoundation capture and guided framing
    Views/       SwiftUI screens, the video overlay, scanning and gyms
    Storage/     local JSON persistence
    Design/      the visual identity as tokens, plus bundled Inter
    Fonts/       Inter Regular, Medium, SemiBold, Bold (SIL OFL)
  Climbing AppTests/   48 known-answer tests
  tools/               demo seeder and mock exporter
mock/            the browser mock of the three screens
identity.html    the published visual identity
```

The Xcode target is called **Climbing App** and the product module is
`ClimbingApp`. The product is branded **Trace**, which is what the bundle
display name and the interface both say.

## Status

Phases 1 to 4 of `PLAN.md` are built, plus route scanning. **Phase 0 has not been run.** Whether Vision
can hold a skeleton on a body pressed against a wall, facing away, with a heel hooked
overhead is still unverified, and it is the question the project lives or dies on.

The capture path has also never executed on real hardware. The simulator has no camera.

One number is picked by judgement rather than derived: `BetaClustering.sameSequenceThreshold`.
It wants calibrating against real footage.
