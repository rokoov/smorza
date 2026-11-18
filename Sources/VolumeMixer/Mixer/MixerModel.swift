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
}

/// Owns the per-app routes: builds a tap for every app that is not at full volume, starts it
/// while the app plays and rebuilds them all when the output device changes.
@MainActor
@Observable
final class MixerModel {
    private(set) var entries: [MixerEntry] = []
    private(set) var permission = AudioCapturePermission.current()
    private(set) var routingError: String?
    /// Set the first time a route delivers real audio. The TCC check cannot be trusted for this
    /// permission (it reports "undetermined" even once allowed), so audio itself is the proof.
    private(set) var isCaptureConfirmed = UserDefaults.standard.bool(forKey: MixerModel.captureConfirmedKey)
    private static let captureConfirmedKey = "CaptureConfirmed"
    let output = SystemOutput()
    /// Off only for the `--snapshot` preview, which must never touch anyone's audio.
    @ObservationIgnored var routesAudio = true

    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let store = AppVolumeStore()
    @ObservationIgnored private var identities: [AudioObjectID: AppIdentity] = [:]
    @ObservationIgnored private var taps: [AudioObjectID: ProcessTap] = [:]
    @ObservationIgnored private var pendingStops: [AudioObjectID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingRemovals: [AudioObjectID: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedAttempts: [AudioObjectID: Int] = [:]
    @ObservationIgnored private var receivingAudio: Set<AudioObjectID> = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var napBlocker: NSObjectProtocol?
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var rowSummary: [String] = []
    @ObservationIgnored private var listedKeys: Set<String> = []

    func start() {
        monitor.onChange = { [weak self] in self?.clientsChanged() }
        output.onDeviceChange = { [weak self] in self?.rebuildRoutes(reason: "output device changed") }
        output.start()
        monitor.start()
        log.notice("Started with audio capture permission \(self.permission.rawValue, privacy: .public)")
    }

    func panelDidAppear() {
        guard !isPanelVisible else { return }
        // Fresh state first, while rows may still reorder; then they hold still until it closes.
        monitor.refreshPlaying()
        output.refreshLevels()
        refreshPermission()
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

    private func apply(_ setting: AppVolume, to key: String) {
        store[key] = setting
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].volume = setting.volume
            entries[index].isMuted = setting.isMuted
        }
        for (objectID, tap) in taps where identities[objectID]?.key == key {
            tap.gain = setting.gain
        }
        // Touching a slider gives an app whose route failed another chance.
        failedAttempts = failedAttempts.filter { identities[$0.key]?.key != key }
        syncRoutes()
    }

    private func clientsChanged() {
        let clients = monitor.clients
        identities = clients.mapValues { resolver.identity(for: $0) }
        resolver.forget(allBut: Set(clients.values.map(\.pid)))
        for objectID in taps.keys.filter({ clients[$0] == nil }) {
            removeRoute(objectID)
        }
        failedAttempts = failedAttempts.filter { clients[$0.key] != nil }
        syncRoutes()
    }

    private func syncRoutes() {
        let canRoute = routesAudio && permission != .denied
        for (objectID, client) in monitor.clients {
            guard let identity = identities[objectID] else { continue }
            let setting = store[identity.key]
            guard canRoute, setting.needsRouting else {
                if taps[objectID] != nil { scheduleRemoval(objectID) }
                continue
            }
            Self.cancel(&pendingRemovals, objectID)
            guard (failedAttempts[objectID] ?? 0) < Tuning.routeAttempts,
                  let tap = taps[objectID] ?? makeRoute(for: objectID, gain: setting.gain) else { continue }
            if client.isPlaying {
                Self.cancel(&pendingStops, objectID)
                startRoute(tap, objectID: objectID)
            } else if tap.isRunning {
                scheduleStop(objectID)
            }
        }
        updateBackgroundWork()
        rebuildEntries()
    }

    private func makeRoute(for objectID: AudioObjectID, gain: Float) -> ProcessTap? {
        guard output.deviceID.isKnown else { return nil }
        do {
            let tap = try ProcessTap(processObjectID: objectID, outputDevice: output.deviceID, gain: gain)
            taps[objectID] = tap
            log.notice("Routing \(self.label(objectID), privacy: .public) to \(tap.deviceUID, privacy: .public)")
            return tap
        } catch {
            recordFailure(objectID, error)
            return nil
        }
    }

    private func startRoute(_ tap: ProcessTap, objectID: AudioObjectID) {
        guard !tap.isRunning else { return }
        do {
            try tap.start()
            failedAttempts[objectID] = nil
            routingError = nil
        } catch {
            recordFailure(objectID, error)
            // The tap mutes the app, so a route that will not start must not stay around.
            if (failedAttempts[objectID] ?? 0) >= Tuning.routeAttempts {
                removeRoute(objectID)
            }
        }
    }

    private func recordFailure(_ objectID: AudioObjectID, _ error: Error) {
        let attempts = (failedAttempts[objectID] ?? 0) + 1
        failedAttempts[objectID] = attempts
        routingError = "\(identities[objectID]?.name ?? "An app"): \(error.localizedDescription)"
        log.error("Route for \(self.label(objectID), privacy: .public) failed (attempt \(attempts)): \(error.localizedDescription, privacy: .public)")
        // A just-made aggregate device is sometimes not ready yet, so try again shortly.
        guard attempts < Tuning.routeAttempts, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Tuning.retryDelay)
            guard let self else { return }
            self.retryTask = nil
            self.syncRoutes()
        }
    }

    private func scheduleStop(_ objectID: AudioObjectID) {
        guard pendingStops[objectID] == nil else { return }
        pendingStops[objectID] = Task { [weak self] in
            try? await Task.sleep(for: Tuning.idleStopDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingStops[objectID] = nil
            guard self.monitor.clients[objectID]?.isPlaying != true else { return }
            self.taps[objectID]?.stop()
            self.receivingAudio.remove(objectID)
            self.updateBackgroundWork()
        }
    }

    private func scheduleRemoval(_ objectID: AudioObjectID) {
        guard pendingRemovals[objectID] == nil else { return }
        pendingRemovals[objectID] = Task { [weak self] in
            try? await Task.sleep(for: Tuning.removeDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingRemovals[objectID] = nil
            let stillWanted = self.permission != .denied
                && (self.identities[objectID].map { self.store[$0.key].needsRouting } ?? false)
            guard !stillWanted else { return }
            self.removeRoute(objectID)
            self.updateBackgroundWork()
        }
    }

    private func removeRoute(_ objectID: AudioObjectID) {
        Self.cancel(&pendingStops, objectID)
        Self.cancel(&pendingRemovals, objectID)
        receivingAudio.remove(objectID)
        guard let tap = taps.removeValue(forKey: objectID) else { return }
        tap.invalidate()
        log.notice("Stopped routing \(self.label(objectID), privacy: .public)")
    }

    /// Builds every route again on the current output device. New routes start before the old
    /// ones go, so the app is never left playing at full volume in between.
    private func rebuildRoutes(reason: String) {
        guard !taps.isEmpty else {
            syncRoutes()
            return
        }
        log.notice("Rebuilding \(self.taps.count) routes: \(reason, privacy: .public)")
        let previous = taps
        taps.removeAll()
        pendingStops.values.forEach { $0.cancel() }
        pendingRemovals.values.forEach { $0.cancel() }
        pendingStops.removeAll()
        pendingRemovals.removeAll()
        receivingAudio.removeAll()
        failedAttempts.removeAll()
        syncRoutes()
        previous.values.forEach { $0.invalidate() }
    }

    private func refreshPermission() {
        let current = AudioCapturePermission.current()
        guard current != permission else { return }
        let previous = permission
        permission = current
        log.notice("Audio capture permission \(previous.rawValue, privacy: .public) -> \(current.rawValue, privacy: .public)")
        switch current {
        case .denied:
            // A denied tap only hears silence while it keeps the app muted: give the sound back.
            for objectID in Array(taps.keys) {
                removeRoute(objectID)
            }
            updateBackgroundWork()
        case .authorized:
            // A route started while the prompt was open can keep delivering silence.
            rebuildRoutes(reason: "permission granted")
        case .undetermined:
            break
        }
    }

    private func updateBackgroundWork() {
        if !taps.isEmpty, napBlocker == nil {
            // App Nap would delay the "started playing" notice and leave a routed app muted for longer.
            napBlocker = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Routing app audio")
        } else if taps.isEmpty, let blocker = napBlocker {
            ProcessInfo.processInfo.endActivity(blocker)
            napBlocker = nil
        }

        // The heartbeat also catches playing changes macOS never announces: a turned-down app that
        // starts playing unnoticed would stay muted by its tap.
        let needsHeartbeat = !taps.isEmpty || isPanelVisible
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
        for (objectID, tap) in taps where tap.isRunning {
            let peak = tap.takePeak()
            if peak > 0, receivingAudio.insert(objectID).inserted {
                log.notice("Receiving audio from \(self.label(objectID), privacy: .public), peak \(peak, format: .fixed(precision: 3))")
                confirmCapture()
            }
        }
        if permission != .authorized {
            refreshPermission()
        }
    }

    private func rebuildEntries() {
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
        let kept = byActivity
            .filter { positions[$0.id] != nil }
            .sorted { positions[$0.id, default: 0] < positions[$1.id, default: 0] }
        return kept + byActivity.filter { positions[$0.id] == nil }
    }

    private static func playingFirst(_ first: MixerEntry, _ second: MixerEntry) -> Bool {
        if first.isPlaying != second.isPlaying { return first.isPlaying }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }

    private func confirmCapture() {
        guard !isCaptureConfirmed else { return }
        isCaptureConfirmed = true
        UserDefaults.standard.set(true, forKey: Self.captureConfirmedKey)
    }

    private func label(_ objectID: AudioObjectID) -> String {
        let name = identities[objectID]?.name ?? "process object"
        let pid = monitor.clients[objectID].map { String($0.pid) } ?? "?"
        return "\(name) (pid \(pid))"
    }

    private static func cancel(_ tasks: inout [AudioObjectID: Task<Void, Never>], _ objectID: AudioObjectID) {
        tasks.removeValue(forKey: objectID)?.cancel()
    }
}
