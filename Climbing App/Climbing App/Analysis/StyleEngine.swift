import Foundation

/// The kinds of climb a person falls off, read across routes.
///
/// "Where you stand" says which movement faults a climber carries from route
/// to route. This says which routes bring them out: dynamic problems or static
/// ones, big moves or small, and, where the climber has said so, which hold
/// types and which angles. Each bucket carries its send rate and the fault
/// that showed up most on it, so the answer is a sentence a coach would say:
/// "you fall off dynamic routes, and on them it is the feet that go first."
///
/// Two of the four axes are measured and two are said. Static versus dynamic
/// and the size of the moves come off the pose. Hold types and wall angle do
/// not: a sloper and a crimp are the same coloured blob to the scanner, and
/// from a phone on the floor facing the wall the lean of an overhang is depth,
/// which a 2D pose cannot see. Those two come from the tags on the notes card,
/// and a route nobody tagged is simply not in those buckets.
enum StyleEngine {

    // MARK: Reading one climb

    struct Reading {
        let dynamicShare: Double?
        let reachTorsos: Double?
    }

    /// Dynamic is the deadpoint detector's word: a hand that landed near an
    /// apex of a rising body was thrown there. The reaches are the reach
    /// detector's, so the two counts are of the same kind of event.
    static func read(frames: [PoseFrame]) -> Reading? {
        guard let reaches = ReachEngine.read(frames: frames)?.reaches,
              reaches.count >= ReachEngine.minimumReaches else { return nil }
        let times = frames.map(\.time)
        let thrown = MetricsEngine.deadpointOffsets(frames: frames, times: times).count
        let travels = reaches.map(\.travelled).sorted()
        return Reading(
            dynamicShare: min(1, Double(thrown) / Double(reaches.count)),
            reachTorsos: travels[travels.count / 2])
    }

    // MARK: Buckets

    /// Above this share of thrown moves a route is a dynamic route.
    static let dynamicCut = 0.25
    /// A middle move of a torso length or more is a route of big moves.
    static let bigReach = 1.0
    /// Distinct routes before anything is shown, the same gate as the patterns.
    static let minimumRoutes = PatternEngine.minimumRoutes
    /// And routes in a bucket before the bucket is a bucket.
    static let minimumPerBucket = 3

    struct Bucket: Identifiable, Equatable {
        let id: String
        let title: String
        let routes: Int
        let sent: Int
        /// The fault seen most on these routes, or nil when they were clean.
        let commonFault: LeakKind?
        var sendRate: Double { Double(sent) / Double(max(routes, 1)) }
    }

    struct Report {
        /// Worst send rate first.
        let buckets: [Bucket]
        let routes: Int
        /// Routes with no tags, which the hold and angle buckets cannot see.
        let untagged: Int
    }

    /// One route as the report sees it: the latest trustworthy attempt's
    /// style, whether any attempt sent, every tag anyone put on it, and the
    /// fault that appeared most across its attempts.
    struct RouteSummary {
        let label: String
        let sent: Bool
        let dynamicShare: Double?
        let reachTorsos: Double?
        let holdTypes: Set<ClimbNotes.HoldType>
        let angle: ClimbNotes.WallAngle?
        let fault: LeakKind?
        var isTagged: Bool { !holdTypes.isEmpty || angle != nil }
    }

    static func routes(from climbs: [Climb]) -> [RouteSummary] {
        let tracked = climbs.filter { $0.metrics.isTrustworthy }
        let byRoute = Dictionary(grouping: tracked) {
            $0.label.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return byRoute.map { key, attempts in
            let newest = attempts.sorted { $0.recordedAt > $1.recordedAt }
            let latest = newest.first!
            var holds: Set<ClimbNotes.HoldType> = []
            for a in attempts { holds.formUnion(a.notes?.holdTypes ?? []) }
            let angle = newest.compactMap { $0.notes?.angle }.first
            return RouteSummary(
                label: key,
                sent: attempts.contains { $0.isSent },
                dynamicShare: latest.metrics.dynamicShare,
                reachTorsos: latest.metrics.reachTorsos,
                holdTypes: holds, angle: angle,
                fault: commonFault(in: attempts.flatMap(\.findings)))
        }
    }

    /// The kind that appears most, ties going to the costlier one.
    static func commonFault(in findings: [Finding]) -> LeakKind? {
        let counts = Dictionary(grouping: findings, by: \.kind)
        return counts.max { a, b in
            if a.value.count != b.value.count { return a.value.count < b.value.count }
            let sa = a.value.map(\.severity).max() ?? .negligible
            let sb = b.value.map(\.severity).max() ?? .negligible
            return sa < sb
        }?.key
    }

    static func report(from climbs: [Climb]) -> Report? {
        let all = routes(from: climbs)
        guard all.count >= minimumRoutes else { return nil }

        var buckets: [Bucket] = []
        func add(_ id: String, _ title: String, _ members: [RouteSummary]) {
            guard members.count >= minimumPerBucket else { return }
            buckets.append(Bucket(
                id: id, title: title, routes: members.count,
                sent: members.filter(\.sent).count,
                commonFault: commonFault(members: members)))
        }

        let styled = all.filter { $0.dynamicShare != nil }
        add("static", "Static routes", styled.filter { $0.dynamicShare! < dynamicCut })
        add("dynamic", "Dynamic routes", styled.filter { $0.dynamicShare! >= dynamicCut })

        let sized = all.filter { $0.reachTorsos != nil }
        add("small", "Small moves", sized.filter { $0.reachTorsos! < bigReach })
        add("big", "Big moves", sized.filter { $0.reachTorsos! >= bigReach })

        for angle in ClimbNotes.WallAngle.allCases {
            add("angle.\(angle.rawValue)", angle.label, all.filter { $0.angle == angle })
        }
        for hold in ClimbNotes.HoldType.allCases {
            add("hold.\(hold.rawValue)", hold.label, all.filter { $0.holdTypes.contains(hold) })
        }

        guard !buckets.isEmpty else { return nil }
        buckets.sort { a, b in
            a.sendRate != b.sendRate ? a.sendRate < b.sendRate : a.title < b.title
        }
        return Report(buckets: buckets, routes: all.count,
                      untagged: all.filter { !$0.isTagged }.count)
    }

    /// The fault named on most of the routes in a bucket.
    static func commonFault(members: [RouteSummary]) -> LeakKind? {
        let faults = members.compactMap(\.fault)
        let counts = Dictionary(grouping: faults, by: { $0 })
        return counts.max { $0.value.count < $1.value.count }?.key
    }

    // MARK: One climb, in words

    /// What this climb was, as the report would file it. Measured words first,
    /// then the tags. Empty when nothing could be read and nothing was said.
    static func words(for climb: Climb) -> [String] {
        var out: [String] = []
        if let d = climb.metrics.dynamicShare { out.append(d >= dynamicCut ? "Dynamic" : "Static") }
        if let r = climb.metrics.reachTorsos { out.append(r >= bigReach ? "Big moves" : "Small moves") }
        if let a = climb.notes?.angle { out.append(a.label) }
        if let h = climb.notes?.holdTypes, !h.isEmpty {
            out += ClimbNotes.HoldType.allCases.filter { h.contains($0) }.map(\.label)
        }
        return out
    }

    /// The buckets this climb falls in, from the report across every route,
    /// so the climb can be set against the others of its kind.
    static func buckets(for climb: Climb, in climbs: [Climb]) -> [Bucket] {
        guard let report = report(from: climbs) else { return [] }
        var ids: Set<String> = []
        if let d = climb.metrics.dynamicShare { ids.insert(d >= dynamicCut ? "dynamic" : "static") }
        if let r = climb.metrics.reachTorsos { ids.insert(r >= bigReach ? "big" : "small") }
        if let a = climb.notes?.angle { ids.insert("angle.\(a.rawValue)") }
        for h in climb.notes?.holdTypes ?? [] { ids.insert("hold.\(h.rawValue)") }
        return report.buckets.filter { ids.contains($0.id) }
    }
}
