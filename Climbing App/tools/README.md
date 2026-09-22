# tools/SeedDemo.swift

Fills the simulator with demo climbs so the app can be shown without a gym.

It draws a synthetic wall and a synthetic climber, then runs the **real**
`MetricsEngine`, `FindingEngine` and `PoseTracker.smooth` over the same joint
positions it used to draw. Only the climber's motion is invented; every number
the app then displays is computed exactly as it would be from a real clip.

Four climbing styles are modelled: `leaky` (bent arms, hips hanging out,
stop-start), `improving` (the leak half fixed), `wandering` (the same boulder
solved by traversing around it) and `tidy`. One clip is deliberately generated
with most frames untrackable, so the demo also shows what the app does when it
could not see clearly.

```bash
swiftc -O -o /tmp/seeddemo tools/SeedDemo.swift \
  Trace/Analysis/*.swift Trace/Models/*.swift Trace/Storage/Store.swift
/tmp/seeddemo "$(xcrun simctl get_app_container booted co.trace.app data)/Documents"
```

Delete `Documents/climbs.json`, `Documents/focus.json` and `Documents/Clips` to
clear it. **This is fabricated data. Never ship it.**
