# Browser mock

A reproduction of Trace's three screens in HTML (`mock/index.html`), so the app
can be shown without Xcode or a device. **It is not the app**: nothing there
records, tracks a pose, or analyses anything.

The climber and the wall are synthetic. The numbers are not. `tools/SeedDemo.swift`
generates the climber, the app's real MetricsEngine, FindingEngine, BetaClustering
and FocusEngine run over those joint positions, and `tools/ExportMock.swift` dumps
the result straight into the payload that is inlined into the page.

That means the mock cannot drift away from the app's behaviour. Change the
clustering threshold, re-export, and the mock changes with it.
