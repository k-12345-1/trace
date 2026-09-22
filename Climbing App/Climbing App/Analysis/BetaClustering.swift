import Foundation
import CoreGraphics

/// Groups attempts on the same climb by the *shape* of the centre-of-mass path.
///
/// This is how Spotter respects the fact that everyone's beta is different. It never
/// reads the wall and never suggests a sequence. It notices when two attempts traced
/// the same shape, and when they traced different ones, and then reports which of
/// your own sequences cost the least.
///
/// Similar path shape means you repeated a sequence, so the question is whether it
/// got smoother. A different shape means you solved it a different way, so the
/// question is which solution was cheaper.
enum BetaClustering {

    /// Distance below which two paths count as the same sequence, in units of path
    /// radius. This is the one number in Spotter picked by judgement rather than
    /// derived, and it wants calibrating against real footage in Phase 0.
    static let sameSequenceThreshold = 0.35

    struct Cluster: Identifiable {
        let id = UUID()
        var climbs: [Climb]
        /// Lowest entropy in the group.
        var cheapest: Climb? {
            climbs.filter { $0.metrics.isTrustworthy }
                  .min { $0.metrics.entropy < $1.metrics.entropy }
        }
        var meanEntropy: Double {
            let vals = climbs.filter { $0.metrics.isTrustworthy }.map(\.metrics.entropy)
            return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
        }
    }

    // MARK: Shape comparison

    /// Resample to a fixed number of points spaced evenly along the path, so two
    /// climbs of different durations and frame counts can be compared point to point.
    static func resample(_ path: [CGPoint], to n: Int = 32) -> [CGPoint] {
        guard path.count > 1, n > 1 else { return path }
        let total = MetricsEngine.pathLength(path)
        guard total > 0 else { return Array(repeating: path[0], count: n) }

        let step = total / Double(n - 1)
        var out: [CGPoint] = [path[0]]
        var travelled = 0.0
        var target = step
        var i = 1

        while i < path.count && out.count < n {
            let segment = MetricsEngine.distance(path[i], path[i - 1])
            if segment <= 0 { i += 1; continue }

            if travelled + segment >= target {
                let t = (target - travelled) / segment
                out.append(CGPoint(
                    x: path[i - 1].x + (path[i].x - path[i - 1].x) * t,
                    y: path[i - 1].y + (path[i].y - path[i - 1].y) * t
                ))
                target += step
            } else {
                travelled += segment
                i += 1
            }
        }
        while out.count < n { out.append(path[path.count - 1]) }
        return out
    }

    /// Centre on the path's centroid and scale by its RMS radius, so a climber who
    /// stood further from the phone is not counted as having climbed differently.
    static func normalise(_ path: [CGPoint]) -> [CGPoint] {
        guard !path.isEmpty else { return path }
        let n = Double(path.count)
        let cx = path.reduce(0.0) { $0 + Double($1.x) } / n
        let cy = path.reduce(0.0) { $0 + Double($1.y) } / n

        let centred = path.map { CGPoint(x: Double($0.x) - cx, y: Double($0.y) - cy) }
        let rms = (centred.reduce(0.0) {
            $0 + Double($1.x * $1.x + $1.y * $1.y)
        } / n).squareRoot()

        guard rms > 1e-6 else { return centred }
        return centred.map { CGPoint(x: Double($0.x) / rms, y: Double($0.y) / rms) }
    }

    /// Mean point-to-point distance between two shape-normalised paths.
    static func shapeDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let pa = normalise(resample(a)), pb = normalise(resample(b))
        guard pa.count == pb.count, !pa.isEmpty else { return .infinity }
        let sum = zip(pa, pb).reduce(0.0) { $0 + MetricsEngine.distance($1.0, $1.1) }
        return sum / Double(pa.count)
    }

    // MARK: Clustering

    /// Single-linkage agglomerative clustering. Attempt counts here are small,
    /// so the naive version is the right one.
    static func cluster(_ climbs: [Climb],
                        threshold: Double = sameSequenceThreshold) -> [Cluster] {
        let usable = climbs.filter { $0.metrics.isTrustworthy && $0.metrics.comPath.count > 4 }
        guard usable.count > 1 else {
            return usable.map { Cluster(climbs: [$0]) }
        }

        var groups: [[Climb]] = usable.map { [$0] }
        var merged = true

        while merged {
            merged = false
            outer: for i in 0..<groups.count {
                for j in (i + 1)..<groups.count {
                    // Single linkage: merge if any pair across the two groups is close.
                    let close = groups[i].contains { a in
                        groups[j].contains { b in
                            shapeDistance(a.metrics.comPath, b.metrics.comPath) < threshold
                        }
                    }
                    if close {
                        groups[i].append(contentsOf: groups[j])
                        groups.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }

        return groups
            .map { Cluster(climbs: $0.sorted { $0.recordedAt < $1.recordedAt }) }
            .sorted { $0.meanEntropy < $1.meanEntropy }
    }

    /// What to tell the climber about a set of attempts, in one sentence.
    static func summary(for clusters: [Cluster], attemptCount: Int) -> String? {
        guard attemptCount > 1 else { return nil }

        if clusters.count == 1, let group = clusters.first, group.climbs.count > 1 {
            let entropies = group.climbs.map(\.metrics.entropy)
            guard let first = entropies.first, let last = entropies.last else { return nil }
            if last < first - 0.02 {
                return "You climbed it the same way each time and it got smoother. That is refinement, and it is what repeating a climb is for."
            } else if last > first + 0.02 {
                return "Same sequence each time, but it got less smooth rather than more. That is usually fatigue rather than technique."
            }
            return "You climbed it the same way each time, with no real change in smoothness yet."
        }

        if clusters.count > 1 {
            return "You solved this \(clusters.count) different ways. The cheapest one is marked below. Spotter will not tell you which holds to use, because that is your call, but it will tell you which of your own sequences cost the least."
        }
        return nil
    }
}
