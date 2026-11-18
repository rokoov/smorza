import AppKit
import CoreAudio
import Foundation
import MixerCore
import Observation

/// One row in the mixer: an app and every process that plays sound for it.
struct MixerEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    var volume: Double
    var isMuted: Bool
    var isPlaying: Bool

    var isAdjusted: Bool { AppVolume(volume: volume, isMuted: isMuted).needsRouting }
}

/// Whether macOS lets the mixer hear other apps (System Audio Recording).
enum CaptureState: Equatable {
    /// Not checked yet, or a failed check is being retried.
    case unknown
    case checking
    case allowed
    case blocked
}

enum Tuning {
    /// How long an app may stay silent before its route stops, so a gap between songs keeps it warm.
    static let idleStopDelay: Duration = .seconds(5)
    /// How long an app sits at full volume before its route is removed, so a slider dragged
    /// through 100% does not tear the route down and build it again.
    static let removeDelay: Duration = .seconds(2)
    /// Attempts at building or starting a route before the app is left to play untouched.
    static let routeAttempts = 3
    static let retryDelay: Duration = .milliseconds(400)
    static let heartbeat: Duration = .seconds(1)
    /// How often a running capture check looks for its signal.
    static let capturePoll: Duration = .milliseconds(100)
    /// A check is rebuilt this often: one started while macOS was still asking may keep hearing
    /// silence after the user allowed it.
    static let captureRestart: Duration = .seconds(5)
    /// How long the user has to answer the macOS prompt before the notice shows.
    static let captureTimeout: Duration = .seconds(30)
    /// Pause after waking from sleep, while devices come back, before routes are rebuilt.
    static let wakeRebuildDelay: Duration = .seconds(2)
}

/// Owns the routes: one tap for every app that is not at full volume, started while the app plays,
/// built only once a capture check proved macOS lets the mixer hear other apps, and rebuilt when
/// the output device changes, the Mac wakes or the audio service restarts.
@MainActor
@Observable
final class MixerModel {
    private(set) var entries: [MixerEntry] = []
    private(set) var captureState = CaptureState.unknown
    /// Keeps the notice up while a retry runs after a failed check.
    private(set) var wasCaptureBlocked = false
    private(set) var routingError: String?
    let output = SystemOutput()
    /// Off only for the `--snapshot` preview, which must never touch anyone's audio.
    @ObservationIgnored var routesAudio = true

    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let store = AppVolumeStore()
    @ObservationIgnored private var identities: [AudioObjectID: AppIdentity] = [:]
    @ObservationIgnored private var routes: [String: ProcessTap] = [:]
    @ObservationIgnored private var pendingStops: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingRemovals: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedAttempts: [String: Int] = [:]
    @ObservationIgnored private var receivingAudio: Set<String> = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var captureCheck: CaptureCheck?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var napBlocker: NSObjectProtocol?
    @ObservationIgnored private var restartListener: PropertyListener?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var rowSummary: [String] = []
    @ObservationIgnored private var listedKeys: Set<String> = []
    @ObservationIgnored private var isDemo = false

    /// Sample rows for README screenshots. The model is never started, so nothing is routed.
    func showDemo(_ demoEntries: [MixerEntry]) {
        isDemo = true
        routesAudio = false
        entries = demoEntries
    }

    func start() {
        monitor.onChange = { [weak self] in self?.clientsChanged() }
        output.onDeviceChange = { [weak self] in self?.outputDeviceChanged() }
        output.start()
        monitor.start()
        listenForServiceRestart()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        }
        log.notice("Started")
    }

    func panelDidAppear() {
        guard !isPanelVisible else { return }
        // Fresh state first, while rows may still reorder; then they hold still until it closes.
        monitor.refreshPlaying()
        output.refreshLevels()
        isPanelVisible = true
        updateBackgroundWork()
        log.notice("Panel opened")
    }

    func panelDidDisappear() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        rebuildEntries()
        updateBackgroundWork()
        log.notice("Panel closed")
    }

    func setVolume(_ volume: Double, for key: String) {
        var setting = store[key]
        setting.volume = min(max(volume, 0), 1)
        apply(setting, to: key)
    }

    func toggleMute(for key: String) {
        var setting = store[key]
        setting.isMuted.toggle()
        apply(setting, to: key)
    }

    func retryCaptureCheck() {
        guard captureState == .blocked else { return }
        captureState = .unknown
        syncRoutes()
    }

    private func apply(_ setting: AppVolume, to key: String) {
        store[key] = setting
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].volume = setting.volume
            entries[index].isMuted = setting.isMuted
        }
        routes[key]?.gain = setting.gain
        // Touching a slider gives a failed route, or a failed capture check, another chance.
        failedAttempts[key] = nil
        if captureState == .blocked {
            captureState = .unknown
        }
        syncRoutes()
    }

    private func clientsChanged() {
        let clients = monitor.clients
        identities = clients.mapValues { resolver.identity(for: $0) }
        resolver.forget(allBut: Set(clients.values.map(\.pid)))
        syncRoutes()
    }

    private func syncRoutes() {
        let apps = Dictionary(grouping: monitor.clients.values) { identities[$0.objectID]?.key ?? "" }
        let wanted = Set(apps.keys.filter { !$0.isEmpty && routesAudio && store[$0].needsRouting })
        if !wanted.isEmpty, captureState != .allowed {
            beginCaptureCheck()
        }

        for key in routes.keys.filter({ apps[$0] == nil }) {
            removeRoute(key)
        }
        for (key, clients) in apps where !key.isEmpty {
            guard wanted.contains(key), captureState == .allowed else {
                if routes[key] != nil { scheduleRemoval(key) }
                continue
            }
            Self.cancel(&pendingRemovals, key)
            let processes = clients.map(\.objectID).sorted()
            guard (failedAttempts[key] ?? 0) < Tuning.routeAttempts,
                let route = route(for: key, processes: processes)
            else { continue }
            if clients.contains(where: \.isPlaying) {
                Self.cancel(&pendingStops, key)
                startRoute(route, key: key)
            } else if route.isRunning {
                scheduleStop(key)
            }
        }
        updateBackgroundWork()
        rebuildEntries()
    }

    private func route(for key: String, processes: [AudioObjectID]) -> ProcessTap? {
        guard let existing = routes[key] else {
            return makeRoute(for: key, processes: processes)
        }
        guard existing.processObjectIDs != processes else { return existing }
        do {
            try existing.setProcesses(processes)
            log.notice("Route for \(self.name(of: key), privacy: .public) now taps \(processes.count) processes")
            return existing
        } catch {
            log.error(
                "Could not update the route for \(self.name(of: key), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            routes[key] = nil
            let replacement = makeRoute(for: key, processes: processes)
            existing.invalidate()
            return replacement
        }
    }

    private func makeRoute(for key: String, processes: [AudioObjectID]) -> ProcessTap? {
        guard output.deviceID.isKnown else { return nil }
        do {
            let route = try ProcessTap(
                label: name(of: key),
                processObjectIDs: processes,
                outputDevice: output.deviceID,
                gain: store[key].gain
            )
            routes[key] = route
            log.notice(
                "Routing \(self.name(of: key), privacy: .public) (\(processes.count) processes) to \(route.deviceUID, privacy: .public)"
            )
            return route
        } catch {
            recordFailure(key, error)
            return nil
        }
    }

    private func startRoute(_ route: ProcessTap, key: String) {
        guard !route.isRunning else { return }
        do {
            try route.start()
            failedAttempts[key] = nil
            routingError = nil
        } catch {
            recordFailure(key, error)
            // The tap mutes the app, so a route that will not start must not stay around.
            if (failedAttempts[key] ?? 0) >= Tuning.routeAttempts {
                removeRoute(key)
            }
        }
    }

    private func recordFailure(_ key: String, _ error: Error) {
        let attempts = (failedAttempts[key] ?? 0) + 1
        failedAttempts[key] = attempts
        routingError = "\(name(of: key)): \(error.localizedDescription)"
        log.error(
            "Route for \(self.name(of: key), privacy: .public) failed (attempt \(attempts)): \(error.localizedDescription, privacy: .public)"
        )
        // A just-made aggregate device is sometimes not ready yet, so try again shortly.
        guard attempts < Tuning.routeAttempts, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Tuning.retryDelay)
            guard let self else { return }
            self.retryTask = nil
            self.syncRoutes()
        }
    }

    private func scheduleStop(_ key: String) {
        guard pendingStops[key] == nil else { return }
        pendingStops[key] = Task { [weak self] in
            try? await Task.sleep(for: Tuning.idleStopDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingStops[key] = nil
            guard !self.isPlaying(key) else { return }
            self.routes[key]?.stop()
            self.receivingAudio.remove(key)
            self.updateBackgroundWork()
        }
    }

    private func scheduleRemoval(_ key: String) {
        guard pendingRemovals[key] == nil else { return }
        pendingRemovals[key] = Task { [weak self] in
            try? await Task.sleep(for: Tuning.removeDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingRemovals[key] = nil
            let stillWanted = self.routesAudio && self.captureState == .allowed && self.store[key].needsRouting
            guard !stillWanted else { return }
            self.removeRoute(key)
            self.updateBackgroundWork()
        }
    }

    private func removeRoute(_ key: String) {
        Self.cancel(&pendingStops, key)
        Self.cancel(&pendingRemovals, key)
        receivingAudio.remove(key)
        guard let route = routes.removeValue(forKey: key) else { return }
        route.invalidate()
        log.notice("Stopped routing \(route.label, privacy: .public)")
    }

    /// Builds every route again on the current output device. New routes start before the old
    /// ones go, so the app is never left playing at full volume in between.
    private func rebuildRoutes(reason: String) {
        guard !routes.isEmpty else {
            syncRoutes()
            return
        }
        log.notice("Rebuilding \(self.routes.count) routes: \(reason, privacy: .public)")
        let previous = routes
        routes.removeAll()
        cancelPendingWork()
        syncRoutes()
        previous.values.forEach { $0.invalidate() }
    }

    private func cancelPendingWork() {
        pendingStops.values.forEach { $0.cancel() }
        pendingRemovals.values.forEach { $0.cancel() }
        pendingStops.removeAll()
        pendingRemovals.removeAll()
        receivingAudio.removeAll()
        failedAttempts.removeAll()
    }

    private func beginCaptureCheck() {
        guard captureState == .unknown, captureCheck == nil, startCaptureCheck() else { return }
        captureState = .checking
        log.notice("Checking that macOS lets the mixer hear other apps")
        let started = ContinuousClock.now
        captureTask = Task { [weak self] in
            var lastStart = started
            while !Task.isCancelled {
                try? await Task.sleep(for: Tuning.capturePoll)
                guard !Task.isCancelled, let self else { return }
                let now = ContinuousClock.now
                if self.captureCheck?.hasHeardSignal == true {
                    self.finishCaptureCheck(allowed: true, after: now - started)
                    return
                }
                if now - started >= Tuning.captureTimeout {
                    self.finishCaptureCheck(allowed: false, after: now - started)
                    return
                }
                if now - lastStart >= Tuning.captureRestart {
                    lastStart = now
                    self.restartCaptureCheck()
                }
            }
        }
        updateBackgroundWork()
    }

    @discardableResult
    private func startCaptureCheck() -> Bool {
        guard output.deviceID.isKnown else { return false }
        do {
            captureCheck = try CaptureCheck(outputDevice: output.deviceID)
            return true
        } catch {
            routingError = "Audio check: \(error.localizedDescription)"
            log.error("Capture check could not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func restartCaptureCheck() {
        captureCheck?.invalidate()
        captureCheck = nil
        startCaptureCheck()
    }

    private func finishCaptureCheck(allowed: Bool, after elapsed: Duration) {
        captureTask?.cancel()
        captureTask = nil
        captureCheck?.invalidate()
        captureCheck = nil
        captureState = allowed ? .allowed : .blocked
        wasCaptureBlocked = !allowed
        log.notice(
            "Capture check \(allowed ? "passed" : "failed", privacy: .public) after \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)"
        )
        syncRoutes()
    }

    private func outputDeviceChanged() {
        if captureCheck != nil {
            restartCaptureCheck()
        }
        rebuildRoutes(reason: "output device changed")
    }

    private func systemDidWake() {
        guard !routes.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Tuning.wakeRebuildDelay)
            self?.rebuildRoutes(reason: "woke from sleep")
        }
    }

    private func listenForServiceRestart() {
        restartListener = PropertyListener(.system, kAudioHardwarePropertyServiceRestarted) { [weak self] in
            self?.audioServiceRestarted()
        }
    }

    /// coreaudiod restarted: every tap, device and listener the mixer had is gone, and their IDs
    /// may already belong to something else, so nothing old is touched.
    private func audioServiceRestarted() {
        log.notice("Audio service restarted, starting over")
        routes.values.forEach { $0.abandon() }
        routes.removeAll()
        cancelPendingWork()
        if let captureCheck {
            captureCheck.abandon()
            self.captureCheck = nil
            captureTask?.cancel()
            captureTask = nil
            captureState = .unknown
        }
        listenForServiceRestart()
        output.start()
        monitor.restart()
    }

    private func updateBackgroundWork() {
        let isBusy = !routes.isEmpty || captureCheck != nil
        if isBusy, napBlocker == nil {
            // App Nap would delay the "started playing" notice and leave a routed app muted for longer.
            napBlocker = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Routing app audio"
            )
        } else if !isBusy, let blocker = napBlocker {
            ProcessInfo.processInfo.endActivity(blocker)
            napBlocker = nil
        }

        // The heartbeat also catches playing changes macOS never announces: a turned-down app that
        // starts playing unnoticed would stay muted by its tap.
        let needsHeartbeat = !routes.isEmpty || isPanelVisible
        if needsHeartbeat, heartbeat == nil {
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Tuning.heartbeat)
                    guard !Task.isCancelled, let self else { return }
                    self.beat()
                }
            }
        } else if !needsHeartbeat {
            heartbeat?.cancel()
            heartbeat = nil
        }
    }

    private func beat() {
        monitor.refreshPlaying()
        for (key, route) in routes where route.isRunning {
            let peak = route.takePeak()
            if peak > 0, receivingAudio.insert(key).inserted {
                log.notice(
                    "Receiving audio from \(self.name(of: key), privacy: .public), peak \(peak, format: .fixed(precision: 3))"
                )
            }
        }
    }

    private func rebuildEntries() {
        guard !isDemo else { return }
        // Once an app has a row it keeps it until it quits, so pausing it or dragging it back to
        // 100% never pulls the row away in the middle of an adjustment.
        listedKeys.formIntersection(identities.values.map(\.key))
        var grouped: [String: MixerEntry] = [:]
        for (objectID, client) in monitor.clients {
            guard let identity = identities[objectID] else { continue }
            let setting = store[identity.key]
            guard client.isPlaying || setting.needsRouting || listedKeys.contains(identity.key) else { continue }
            if grouped[identity.key] == nil {
                grouped[identity.key] = MixerEntry(
                    id: identity.key,
                    name: identity.name,
                    icon: identity.icon,
                    volume: setting.volume,
                    isMuted: setting.isMuted,
                    isPlaying: client.isPlaying
                )
            } else if client.isPlaying {
                grouped[identity.key]?.isPlaying = true
            }
        }
        listedKeys.formUnion(grouped.keys)
        let ordered = order(Array(grouped.values))
        if ordered != entries {
            entries = ordered
        }
        let summary = ordered.map { $0.isPlaying ? "\($0.name) (playing)" : $0.name }
        if summary != rowSummary {
            rowSummary = summary
            log.notice("Rows: \(summary.isEmpty ? "none" : summary.joined(separator: ", "), privacy: .public)")
        }
    }

    /// Apps making sound come first, where the hand goes most often. While the panel is open the
    /// rows keep their places instead, so nothing moves under the pointer.
    private func order(_ fresh: [MixerEntry]) -> [MixerEntry] {
        let byActivity = fresh.sorted(by: Self.playingFirst)
        guard isPanelVisible else { return byActivity }
        let positions = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
        let kept =
            byActivity
            .filter { positions[$0.id] != nil }
            .sorted { positions[$0.id, default: 0] < positions[$1.id, default: 0] }
        return kept + byActivity.filter { positions[$0.id] == nil }
    }

    private static func playingFirst(_ first: MixerEntry, _ second: MixerEntry) -> Bool {
        if first.isPlaying != second.isPlaying { return first.isPlaying }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }

    private func isPlaying(_ key: String) -> Bool {
        monitor.clients.values.contains { $0.isPlaying && identities[$0.objectID]?.key == key }
    }

    private func name(of key: String) -> String {
        identities.values.first { $0.key == key }?.name ?? key
    }

    private static func cancel(_ tasks: inout [String: Task<Void, Never>], _ key: String) {
        tasks.removeValue(forKey: key)?.cancel()
    }
}
