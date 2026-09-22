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
    @Published private(set) var routes: [Route] = []

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

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(climbs) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
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

    // MARK: Attempt grouping
    //
    // Attempts on the same route, grouped by the free-text label the user typed.
    // This is what makes attempt-over-attempt comparison possible without the app
    // ever knowing anything about the wall.

    func attempts(matching label: String) -> [Climb] {
        let key = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return [] }
        return climbs
            .filter { $0.label.trimmingCharacters(in: .whitespaces).lowercased() == key }
            .sorted { $0.recordedAt < $1.recordedAt }
    }
}
