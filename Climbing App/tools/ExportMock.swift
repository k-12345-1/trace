import Foundation
import CoreGraphics

// Reads the seeded climbs.json and writes a compact payload for the browser mock.
//
// It runs the app's own BetaClustering and FocusEngine rather than restating their
// results, so the mock cannot drift away from what the app actually shows.
//
// Usage: exportmock <Documents dir> <output.json>

let args = CommandLine.arguments
guard args.count > 2 else {
    FileHandle.standardError.write(Data("usage: exportmock <Documents> <out.json>\n".utf8))
    exit(2)
}
let documents = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let climbs = try decoder.decode([Climb].self,
                                from: Data(contentsOf: documents.appendingPathComponent("climbs.json")))
let focus = try? decoder.decode(Focus.self,
                                from: Data(contentsOf: documents.appendingPathComponent("focus.json")))

func r(_ v: Double, _ places: Int = 3) -> Double {
    let f = pow(10.0, Double(places))
    return (v * f).rounded() / f
}

let df = DateFormatter()
df.dateFormat = "d MMM"

// Joint order the mock draws with.
let order: [JointID] = [.nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                        .leftWrist, .rightWrist, .leftHip, .rightHip,
                        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]

func pack(_ climb: Climb, stride step: Int) -> [String: Any] {
    var frames: [[Double]] = []
    for (i, f) in climb.frames.enumerated() where i % step == 0 {
        guard f.meanConfidence > 0 else { continue }
        var flat: [Double] = [r(f.time, 2)]
        for id in order {
            if let j = f.joints[id], j.isUsable {
                flat.append(r(j.x)); flat.append(r(j.y))
            } else {
                flat.append(-1); flat.append(-1)
            }
        }
        frames.append(flat)
    }
    let m = climb.metrics
    return [
        "label": climb.label,
        "date": df.string(from: climb.recordedAt),
        "duration": r(m.duration, 1),
        "entropy": r(m.entropy, 2),
        "logJerk": r(m.logJerk, 1),
        "pathRatio": r(m.pathRatio, 2),
        "elbow": Int(m.staticElbowAngle.rounded()),
        "hips": r(m.comOffsetFromFeet, 2),
        "stops": m.pauseCount,
        "stopSeconds": Int(m.pauseTotal.rounded()),
        "feet": m.footAdjustments,
        "hasDynos": m.hasDynamicMoves,
        "deadpoint": Int(m.meanDeadpointError.rounded()),
        "tracking": Int(m.trackingConfidence * 100),
        "comPath": m.comPath.map { [r(Double($0.x)), r(Double($0.y))] },
        "frames": frames,
        "findings": climb.findings.map { f -> [String: Any] in
            ["title": f.kind.title, "severity": f.severity.rawValue,
             "severityLabel": f.severity.label, "message": f.message,
             "drill": f.kind.drill, "timecode": f.timecode,
             "seconds": r(f.duration, 1)]
        }
    ]
}

// The climb the mock opens on: one with several attempts, so the clustering shows.
let detailLabel = "Blue slab by the fan"
let attempts = climbs.filter { $0.label == detailLabel && $0.metrics.isTrustworthy }
    .sorted { $0.recordedAt < $1.recordedAt }

// The app's own clustering, lettered by when each sequence was first tried.
let clusters = BetaClustering.cluster(attempts).sorted {
    ($0.climbs.first?.recordedAt ?? .distantPast) < ($1.climbs.first?.recordedAt ?? .distantPast)
}
let cheapest = attempts.min { $0.metrics.entropy < $1.metrics.entropy }

var clusterOut: [[String: Any]] = []
for (i, c) in clusters.enumerated() {
    clusterOut.append([
        "letter": String(UnicodeScalar(65 + i)!),
        "cheapest": c.climbs.contains { $0.id == cheapest?.id },
        "attempts": c.climbs.map { climb -> [String: Any] in
            ["index": (attempts.firstIndex { $0.id == climb.id } ?? 0) + 1,
             "entropy": r(climb.metrics.entropy, 2),
             "cheapest": climb.id == cheapest?.id]
        }
    ])
}

let tracked = climbs.filter { $0.metrics.isTrustworthy }.sorted { $0.recordedAt < $1.recordedAt }
var tally: [LeakKind: Int] = [:]
for c in tracked.suffix(12) { if let t = c.findings.first { tally[t.kind, default: 0] += 1 } }

var payload: [String: Any] = [
    "list": climbs.sorted { $0.recordedAt > $1.recordedAt }.map { c -> [String: Any] in
        ["label": c.label, "date": df.string(from: c.recordedAt),
         "entropy": r(c.metrics.entropy, 2),
         "tracked": c.metrics.isTrustworthy,
         "severity": c.findings.first?.severity.rawValue ?? -1]
    },
    "trend": tracked.suffix(12).map { r($0.metrics.entropy, 2) },
    "tally": tally.sorted { $0.value > $1.value }.map {
        ["title": $0.key.title, "count": $0.value]
    },
    "trackedCount": tracked.suffix(12).count,
    "detail": pack(attempts.first!, stride: 3),
    "clusters": clusterOut,
    "summary": BetaClustering.summary(for: clusters, attemptCount: attempts.count) ?? ""
]

if let focus {
    let latest = FocusEngine.currentValue(for: focus.kind, in: climbs.sorted { $0.recordedAt > $1.recordedAt })
        ?? focus.latest
    var live = focus
    live.latest = latest
    payload["focus"] = [
        "title": focus.kind.title,
        "baseline": FocusEngine.format(kind: focus.kind, value: focus.baseline),
        "latest": FocusEngine.format(kind: focus.kind, value: latest),
        "progress": r(live.progress, 3),
        "days": live.daysActive,
        "drill": focus.kind.drill,
        "meaning": FocusEngine.meaning(for: focus.kind),
        "greeting": FocusEngine.greeting(for: live)
    ]
}

let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
try data.write(to: outURL)
print("wrote \(outURL.lastPathComponent), \(data.count / 1024) KB")
