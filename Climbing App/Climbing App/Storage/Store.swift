import Foundation
import SwiftUI

/// Everything stays on the phone. Nothing is uploaded, so there is no account,
/// no backend, and no question about filming other people in a gym.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var climbs: [Climb] = []
    /// The one thing you are working on. Persists across sessions until it improves.
    @Published private(set) var focus: Focus?
    @Published private(set) var gyms: [Gym] = []
    /// Who is signed in. Identity only: nothing about this moves climbs off the phone.
    @Published private(set) var account: Account?
    /// Whether this sign-in should survive the app closing.
    ///
    /// nil means the question has not been put yet, which is the state straight
    /// after signing in. The answer needs no file of its own: keeping someone
    /// signed in *is* writing their account to disk, so the presence of that
    /// file at launch is the answer.
    @Published private(set) var staySignedIn: Bool?
    @Published private(set) var session: Session?
    @Published private(set) var routes: [Route] = []
    /// Your height and reach. Optional: everything works without it, in body lengths.
    @Published private(set) var body: BodyProfile = .empty

    static let shared = Store()

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    nonisolated static var videosDirectory: URL {
        let url = documents.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    nonisolated private static var indexURL: URL { documents.appendingPathComponent("climbs.json") }
    nonisolated private static var focusURL: URL { documents.appendingPathComponent("focus.json") }
    nonisolated private static var gymsURL: URL { documents.appendingPathComponent("gyms.json") }
    nonisolated private static var routesURL: URL { documents.appendingPathComponent("routes.json") }
    nonisolated private static var accountURL: URL { documents.appendingPathComponent("account.json") }
    nonisolated private static var bodyURL: URL { documents.appendingPathComponent("body.json") }

    nonisolated static var routePhotosDirectory: URL {
        let url = documents.appendingPathComponent("Routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() { load() }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: Self.indexURL) {
            climbs = (try? decoder.decode([Climb].self, from: data))?
                .sorted { $0.recordedAt > $1.recordedAt } ?? []
        }
        if let data = try? Data(contentsOf: Self.focusURL) {
            focus = try? decoder.decode(Focus.self, from: data)
        }
        if let data = try? Data(contentsOf: Self.gymsURL) {
            gyms = (try? decoder.decode([Gym].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: Self.routesURL) {
            routes = (try? decoder.decode([Route].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: Self.accountURL) {
            account = try? decoder.decode(Account.self, from: data)
        }
        // An account on disk is someone who asked to be kept signed in, so they
        // go straight through rather than being asked again.
        staySignedIn = account != nil ? true : nil
        if let data = try? Data(contentsOf: Self.bodyURL) {
            body = (try? decoder.decode(BodyProfile.self, from: data)) ?? .empty
        }
        // The tokens live in the keychain, never beside the climbs.
        session = Keychain.load()

        // Re-judge the focus at launch. Without this a focus that was already met
        // keeps showing as open until the next climb happens to be saved.
        refreshFocus()
    }

    func save(_ climb: Climb) {
        climbs.insert(climb, at: 0)
        persist()
        refreshFocus()
    }

    func delete(_ climb: Climb) {
        try? FileManager.default.removeItem(at: climb.videoURL)
        Thumbnails.remove(for: climb)
        climbs.removeAll { $0.id == climb.id }
        persist()
        refreshFocus()
    }

    // MARK: Focus

    func refreshFocus() {
        focus = FocusEngine.evaluate(existing: focus, climbs: climbs)
        persistFocus()
    }

    /// Retire the current focus by hand, for when the climber disagrees with it.
    func dismissFocus() {
        guard var f = focus else { return }
        f.resolvedAt = Date()
        focus = f
        persistFocus()
    }

    private func persistFocus() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let focus, let data = try? encoder.encode(focus) else {
            try? FileManager.default.removeItem(at: Self.focusURL)
            return
        }
        try? data.write(to: Self.focusURL, options: .atomic)
    }

    func rename(_ climb: Climb, to label: String) {
        guard let i = climbs.firstIndex(where: { $0.id == climb.id }) else { return }
        climbs[i].label = label
        persist()
    }

    /// Renames every attempt in a library entry at once.
    ///
    /// The entry only exists because its attempts share a label, so renaming one
    /// of them would silently split the route in two.
    func rename(_ entry: LibraryEntry, to label: String) {
        let ids = Set(entry.attempts.map(\.id))
        for i in climbs.indices where ids.contains(climbs[i].id) {
            climbs[i].label = label
        }
        persist()
    }

    /// Deletes every attempt in a library entry.
    func delete(_ entry: LibraryEntry) {
        for climb in entry.attempts {
            try? FileManager.default.removeItem(at: climb.videoURL)
            Thumbnails.remove(for: climb)
        }
        let ids = Set(entry.attempts.map(\.id))
        climbs.removeAll { ids.contains($0.id) }
        persist()
        refreshFocus()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(climbs) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }

    // MARK: Account

    /// Signs in for this session only. Nothing is written until the climber
    /// says whether they want to be kept signed in, so declining costs no
    /// cleanup: there is simply nothing on disk to remove.
    func signedIn(session: Session, name: String = "") {
        self.session = session
        var acc = Account.signedIn(session: session, name: name)
        // Keep a name already typed on this phone rather than losing it on sign-in.
        if acc.name.isEmpty, let existing = account, !existing.name.isEmpty {
            acc.name = existing.name
        }
        account = acc
        staySignedIn = nil
    }

    /// The answer to that question.
    func keepSignedIn(_ keep: Bool) {
        staySignedIn = keep
        guard keep else { return }
        if let session { Keychain.save(session) }
        persistAccount()
    }

    func continueLocally(name: String) {
        session = nil
        Keychain.clear()
        account = .local(name: name)
        persistAccount()
    }

    /// Clears the identity and the tokens. Climbs are not touched: they belong to
    /// the phone, and signing out of an identity should never delete a person's
    /// training history.
    func signOut() {
        if let session { Task { await AuthClient.signOut(session: session) } }
        session = nil
        account = nil
        Keychain.clear()
        try? FileManager.default.removeItem(at: Self.accountURL)
    }

    /// Refreshes an expired token in the background. A failure is not fatal:
    /// everything the app does works offline anyway.
    func refreshSessionIfNeeded() async {
        guard let current = session, current.isExpired, AuthClient.isConfigured else { return }
        if let renewed = try? await AuthClient.refresh(session: current) {
            session = renewed
            Keychain.save(renewed)
        }
    }

    private func persistAccount() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let account, let data = try? e.encode(account) else { return }
        try? data.write(to: Self.accountURL, options: .atomic)
    }

    // MARK: Gyms and routes

    @discardableResult
    func addGym(named name: String) -> Gym {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = gyms.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) { return existing }
        let gym = Gym(name: trimmed)
        gyms.append(gym)
        persistGyms()
        return gym
    }

    func deleteGym(_ gym: Gym) {
        routes.filter { $0.gymID == gym.id }.forEach { deleteRoute($0) }
        gyms.removeAll { $0.id == gym.id }
        persistGyms()
    }

    func save(_ route: Route) {
        if let i = routes.firstIndex(where: { $0.id == route.id }) {
            routes[i] = route
        } else {
            routes.insert(route, at: 0)
        }
        persistRoutes()
    }

    func deleteRoute(_ route: Route) {
        try? FileManager.default.removeItem(at: route.photoURL)
        routes.removeAll { $0.id == route.id }
        persistRoutes()
    }

    func toggleSent(_ route: Route) {
        guard let i = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[i].sent.toggle()
        persistRoutes()
    }

    func routes(in gym: Gym) -> [Route] {
        routes.filter { $0.gymID == gym.id }.sorted { $0.scannedAt > $1.scannedAt }
    }

    func routeCount(in gym: Gym) -> (total: Int, sent: Int) {
        let r = routes(in: gym)
        return (r.count, r.filter(\.sent).count)
    }

    /// Writes a scanned wall photo into the container and returns its filename.
    func saveRoutePhoto(_ data: Data) throws -> String {
        let name = "\(UUID().uuidString).jpg"
        try data.write(to: Self.routePhotosDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    private func persistGyms() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(gyms).write(to: Self.gymsURL, options: .atomic)
    }
    private func persistRoutes() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(routes).write(to: Self.routesURL, options: .atomic)
    }

    /// Copies a clip into the app container and keeps the returned filename.
    func importVideo(from source: URL) throws -> String {
        let name = "\(UUID().uuidString).mov"
        let dest = Self.videosDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: dest)
        return name
    }

    /// Removes everything Trace holds on this phone, then signs out.
    ///
    /// Local only, because that is where everything is. When there is a server
    /// behind the account this must also call its delete endpoint: an account
    /// that survives on a server after the app says it is gone would be a lie,
    /// and App Review treats it as one.
    func deleteEverything() {
        for climb in climbs {
            try? FileManager.default.removeItem(at: climb.videoURL)
            Thumbnails.remove(for: climb)
        }
        for url in [Self.indexURL, Self.focusURL, Self.gymsURL,
                    Self.routesURL, Self.accountURL, Self.bodyURL] {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: Self.routePhotosDirectory)
        try? FileManager.default.removeItem(at: Self.videosDirectory)
        try? FileManager.default.removeItem(at: Thumbnails.directory)

        climbs = []; focus = nil; gyms = []; routes = []; body = .empty
        Keychain.clear()
        session = nil
        account = nil
    }

    // MARK: Body

    func updateBody(_ profile: BodyProfile) {
        body = profile
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(profile).write(to: Self.bodyURL, options: .atomic)
    }

    // MARK: Attempt grouping
    //
    // Attempts on the same route, grouped by the free-text label the user typed.
    // This is what makes attempt-over-attempt comparison possible without the app
    // ever knowing anything about the wall.

    /// The library: one entry per route, every attempt on it gathered together.
    /// Untitled climbs stay separate, because an empty label is not a route name
    /// shared with anything else.
    func library() -> [LibraryEntry] {
        var grouped: [String: [Climb]] = [:]
        var loose: [Climb] = []
        for climb in climbs {
            let key = climb.label.trimmingCharacters(in: .whitespaces).lowercased()
            if key.isEmpty { loose.append(climb) } else { grouped[key, default: []].append(climb) }
        }
        var out = grouped.values.map { LibraryEntry(attempts: $0) }
        out += loose.map { LibraryEntry(attempts: [$0]) }
        return out.sorted { $0.lastClimbed > $1.lastClimbed }
    }

    /// Marks one attempt as topped out, or un-marks it.
    func toggleSent(_ climb: Climb) {
        guard let i = climbs.firstIndex(where: { $0.id == climb.id }) else { return }
        climbs[i].sent = !(climbs[i].sent ?? false)
        persist()
    }

    func attempts(matching label: String) -> [Climb] {
        let key = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return [] }
        return climbs
            .filter { $0.label.trimmingCharacters(in: .whitespaces).lowercased() == key }
            .sorted { $0.recordedAt < $1.recordedAt }
    }
}
