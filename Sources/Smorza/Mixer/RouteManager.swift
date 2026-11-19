import CoreAudio
import Foundation
import Observation

/// Builds, starts, stops and removes the routes: one muted tap per turned-down app, played back at
/// the app's volume on the app's output device.
@MainActor
@Observable
final class RouteManager {
    /// What one app needs from its route right now.
    struct Request {
        let key: String
        let label: String
        let processObjectIDs: [AudioObjectID]
        let outputDevice: AudioObjectID
        let gain: Float
        let isPlaying: Bool
        let isWanted: Bool
    }

    enum Timing {
        /// Silence an app may keep before its route stops, so a gap between songs keeps it warm.
        static let idleStop: Duration = .seconds(5)
        /// Time an app sits at full volume before its route goes, so a slider dragged through 100%
        /// does not tear the route down and build it again.
        static let removal: Duration = .seconds(2)
        /// Pause before trying again; a just-made aggregate device is sometimes not ready yet.
        static let retry: Duration = .milliseconds(400)
        /// Attempts at building or starting a route before the app is left to play untouched.
        static let attempts = 3
    }

    private(set) var lastError: String?
    /// Asks the owner for a fresh `sync` once a retry is due.
    @ObservationIgnored var onRetry: (() -> Void)?
    /// Tells the owner a route went away on its own (removed after a delay).
    @ObservationIgnored var onRoutesChanged: (() -> Void)?

    @ObservationIgnored private var routes: [String: ProcessTap] = [:]
    @ObservationIgnored private var requests: [String: Request] = [:]
    @ObservationIgnored private var pendingStops: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingRemovals: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedAttempts: [String: Int] = [:]
    @ObservationIgnored private var receivingAudio: Set<String> = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    var isEmpty: Bool { routes.isEmpty }

    /// Brings every route in line with what its app needs now. A route on another output device
    /// than its app wants is replaced, and the old one only goes once the new one has started, so
    /// the app never plays at full volume in between.
    func sync(_ newRequests: [Request]) {
        requests = Dictionary(newRequests.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for key in routes.keys.filter({ requests[$0] == nil }) {
            remove(key)
        }

        var retired: [ProcessTap] = []
        for request in newRequests {
            guard request.isWanted else {
                if routes[request.key] != nil { scheduleRemoval(request.key) }
                continue
            }
            Self.cancel(&pendingRemovals, request.key)
            guard failedAttempts[request.key, default: 0] < Timing.attempts,
                let route = route(for: request, retiring: &retired)
            else { continue }
            route.gain = request.gain
            if request.isPlaying {
                Self.cancel(&pendingStops, request.key)
                start(route, key: request.key)
            } else if route.isRunning {
                scheduleStop(request.key)
            }
        }
        for route in retired {
            route.invalidate()
        }
    }

    /// Builds every route again, for after the Mac wakes and devices may have reset.
    func rebuildAll(reason: String) {
        guard !routes.isEmpty else { return }
        log.notice("Rebuilding \(self.routes.count) routes: \(reason, privacy: .public)")
        let previous = Array(routes.values)
        routes.removeAll()
        cancelPendingWork()
        sync(Array(requests.values))
        for route in previous {
            route.invalidate()
        }
    }

    /// Takes every route down, for when the mixer quits.
    func shutDown() {
        cancelPendingWork()
        for route in routes.values {
            route.invalidate()
        }
        routes.removeAll()
    }

    /// Forgets every route without touching it. After coreaudiod restarts the routes are gone and
    /// their IDs may already belong to something else.
    func abandonAll() {
        for route in routes.values {
            route.abandon()
        }
        routes.removeAll()
        cancelPendingWork()
    }

    /// One line per route and per app whose route keeps failing, for Copy Diagnostics.
    func summary() -> [String] {
        let running = routes.keys.sorted().compactMap { key -> String? in
            guard let route = routes[key] else { return nil }
            let state =
                route.isRunning ? (receivingAudio.contains(key) ? "running, audio heard" : "running") : "stopped"
            return "\(route.label) to \(route.deviceUID): \(state), gain \(String(format: "%.3f", route.gain))"
        }
        let failing = failedAttempts.keys.sorted().map { "\($0): \(failedAttempts[$0, default: 0]) failed attempts" }
        return running + failing
    }

    /// Gives an app whose route failed another chance, after the user touched its slider.
    func clearFailures(for key: String) {
        failedAttempts[key] = nil
    }

    /// Reads how loud each running route has been since the last call, as it leaves the route
    /// (the app's peak times its gain), and logs the first real audio each one delivers, which proves
    /// the route works. Reading resets the peaks, so one caller samples at a time.
    func sampleLevels() -> [String: Float] {
        var levels: [String: Float] = [:]
        for (key, route) in routes where route.isRunning {
            let peak = route.takePeak()
            levels[key] = min(peak * route.gain, 1)
            if peak > 0, receivingAudio.insert(key).inserted {
                let label = route.label
                log.notice(
                    "Receiving audio from \(label, privacy: .public), peak \(peak, format: .fixed(precision: 3))"
                )
            }
        }
        return levels
    }

    private func route(for request: Request, retiring retired: inout [ProcessTap]) -> ProcessTap? {
        guard let existing = routes[request.key] else { return makeRoute(for: request) }
        if existing.outputDevice != request.outputDevice {
            routes[request.key] = nil
            receivingAudio.remove(request.key)
            retired.append(existing)
            return makeRoute(for: request)
        }
        guard existing.processObjectIDs != request.processObjectIDs else { return existing }
        let label = existing.label
        do {
            try existing.setProcesses(request.processObjectIDs)
            log.notice("Route for \(label, privacy: .public) now taps \(request.processObjectIDs.count) processes")
            return existing
        } catch {
            log.error("Could not update the route for \(label, privacy: .public): \(error.localizedDescription)")
            routes[request.key] = nil
            retired.append(existing)
            return makeRoute(for: request)
        }
    }

    private func makeRoute(for request: Request) -> ProcessTap? {
        guard request.outputDevice.isKnown else { return nil }
        do {
            let route = try ProcessTap(
                label: request.label,
                processObjectIDs: request.processObjectIDs,
                outputDevice: request.outputDevice,
                gain: request.gain
            )
            routes[request.key] = route
            let processCount = request.processObjectIDs.count
            log.notice(
                "Routing \(request.label, privacy: .public) (\(processCount) processes) to \(route.deviceUID, privacy: .public)"
            )
            return route
        } catch {
            recordFailure(key: request.key, label: request.label, error)
            return nil
        }
    }

    private func start(_ route: ProcessTap, key: String) {
        guard !route.isRunning else { return }
        do {
            try route.start()
            failedAttempts[key] = nil
            lastError = nil
        } catch {
            recordFailure(key: key, label: route.label, error)
            // The tap mutes the app, so a route that will not start must not stay around.
            if failedAttempts[key, default: 0] >= Timing.attempts {
                remove(key)
            }
        }
    }

    private func recordFailure(key: String, label: String, _ error: Error) {
        let attempts = failedAttempts[key, default: 0] + 1
        failedAttempts[key] = attempts
        lastError = "\(label): \(error.localizedDescription)"
        log.error(
            "Route for \(label, privacy: .public) failed (attempt \(attempts)): \(error.localizedDescription, privacy: .public)"
        )
        guard attempts < Timing.attempts, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Timing.retry)
            guard let self else { return }
            retryTask = nil
            onRetry?()
        }
    }

    private func scheduleStop(_ key: String) {
        guard pendingStops[key] == nil else { return }
        pendingStops[key] = Task { [weak self] in
            try? await Task.sleep(for: Timing.idleStop)
            guard !Task.isCancelled, let self else { return }
            pendingStops[key] = nil
            guard requests[key]?.isPlaying != true else { return }
            routes[key]?.stop()
            receivingAudio.remove(key)
        }
    }

    private func scheduleRemoval(_ key: String) {
        guard pendingRemovals[key] == nil else { return }
        pendingRemovals[key] = Task { [weak self] in
            try? await Task.sleep(for: Timing.removal)
            guard !Task.isCancelled, let self else { return }
            pendingRemovals[key] = nil
            guard requests[key]?.isWanted != true else { return }
            remove(key)
            onRoutesChanged?()
        }
    }

    private func remove(_ key: String) {
        Self.cancel(&pendingStops, key)
        Self.cancel(&pendingRemovals, key)
        receivingAudio.remove(key)
        guard let route = routes.removeValue(forKey: key) else { return }
        route.invalidate()
        let label = route.label
        log.notice("Stopped routing \(label, privacy: .public)")
    }

    private func cancelPendingWork() {
        for task in pendingStops.values {
            task.cancel()
        }
        for task in pendingRemovals.values {
            task.cancel()
        }
        pendingStops.removeAll()
        pendingRemovals.removeAll()
        receivingAudio.removeAll()
        failedAttempts.removeAll()
    }

    private static func cancel(_ tasks: inout [String: Task<Void, Never>], _ key: String) {
        tasks.removeValue(forKey: key)?.cancel()
    }
}
