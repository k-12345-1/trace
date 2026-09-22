# Spotter

An iOS training partner for bouldering. Point your phone at yourself, climb, and it
tells you one thing you could do better, with the moment highlighted on your own video.

Spotter never tells you which holds to use. Everyone's beta is different, so it
measures how well you executed the sequence you chose, not which sequence you chose.
That constraint is why it needs no route database, no hold detection and no gym
partnership: it works anywhere, from the first climb.

## Running it

```bash
open Spotter/Spotter.xcodeproj
```

Build and run on a device. The simulator has no camera, so use **Import a clip**
there. Tests run with `cmd-U`, or:

```bash
xcodebuild test -project Spotter/Spotter.xcodeproj -scheme Spotter \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

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

Below 55 percent tracking confidence Spotter draws nothing and says nothing.
Confidently wrong coaching is the failure mode that kills this product.

## Layout

```
Spotter/Spotter/
  Analysis/    pose tracking, metrics, findings, focus, beta clustering
  Models/      climb, pose, focus
  Capture/     AVFoundation capture and guided framing
  Views/       SwiftUI screens and the video overlay
  Storage/     local JSON persistence
  Design/      the Spotter visual identity as tokens
SpotterTests/  36 known-answer tests
```

## Status

Phases 1 to 4 of `../PLAN.md` are built. **Phase 0 has not been run.** Whether Vision
can hold a skeleton on a body pressed against a wall, facing away, with a heel hooked
overhead is still unverified, and it is the question the project lives or dies on.

The capture path has also never executed on real hardware. The simulator has no camera.

One number is picked by judgement rather than derived: `BetaClustering.sameSequenceThreshold`.
It wants calibrating against real footage.
