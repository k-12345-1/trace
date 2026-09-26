# Screenshots

Four screens at 1320×2868, which is the 6.9" size App Store Connect asks for.

**These are reference, not submissions.** The climbs in them are the synthetic
demo climber from `tools/SeedDemo.swift`: a grey stick figure on a black wall.
They show which four screens to shoot and what each should be showing. The real
set has to be your own climbing, filmed in the app.

To retake them: seed a 6.9" simulator per `tools/README.md`, then
`xcrun simctl io <udid> screenshot`.

| File | Screen | What it should show |
|---|---|---|
| `1-home.png` | Home | The working-on card, your gyms, a library with real thumbnails |
| `2-route.png` | A route | Attempts against one problem, with grades |
| `3-overlay.png` | Playback | The skeleton, the elbow angles, the balance circle |
| `4-efficiency.png` | Efficiency | The grade and every component behind it |
