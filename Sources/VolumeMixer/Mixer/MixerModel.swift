import AppKit
import CoreAudio
import Foundation
import MixerCore
import Observation

/// The state the panel shows, and the link between the audio clients, the saved settings, the
/// capture check and the routes.
@MainActor
@Observable
final class MixerModel {
    enum Timing {
        /// How often playing states are read again while routing or while the panel is open,
        /// because macOS does not announce every change.
        static let heartbeat: Duration = .seconds(1)
        /// Pause after waking from sleep, while devices come back, before routes are rebuilt.
        static let wakeRebuild: Duration = .seconds(2)
    }

    private(set) var entries: [MixerEntry] = []
    let output = SystemOutput()
    /// Off only for the `--snapshot` previews, which must never touch anyone's audio.
    @ObservationIgnored var routesAudio = true

    private let capture = CaptureCheckController()
    private let routes = RouteManager()
    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let store = AppVolumeStore()
    @ObservationIgnored private var identities: [AudioObjectID: AppIdentity] = [:]
    @ObservationIgnored private var listedKeys: Set<String> = []
    @ObservationIgnored private var rowSummary: [String] = []
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var isDemo = false
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var napBlocker: NSObjectProtocol?
    @ObservationIgnored private var restartListener: PropertyListener?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    var captureState: CaptureCheckController.State { capture.state }
    var wasCaptureBlocked: Bool { capture.wasBlocked }
    var routingError: String? { routes.lastError ?? capture.lastError }

    func start() {
        monitor.onChange = { [weak self] in self?.clientsChanged() }
        output.onDeviceChange = { [weak self] in self?.outputDeviceChanged() }
        capture.onFinish = { [weak self] in self?.syncRoutes() }
        routes.onRetry = { [weak self] in self?.syncRoutes() }
        routes.onRoutesChanged = { [weak self] in self?.updateBackgroundWork() }
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

    /// Sample rows for README screenshots. The model is never started, so nothing is routed.
    func showDemo(_ demoEntries: [MixerEntry]) {
        isDemo = true
        routesAudio = false
        entries = demoEntries
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
        rebuildEntries(from: currentApps())
        updateBackgroundWork()
        log.notice("Panel closed")
    }

    func setVolume(_ volume: Double, for key: String) {
        var setting = store[key]
        setting.volume = min(max(volume, 0), VolumeCurve.maximum)
        apply(setting, to: key)
    }

    func toggleMute(for key: String) {
        var setting = store[key]
        setting.isMuted.toggle()
        apply(setting, to: key)
    }

    func retryCaptureCheck() {
        capture.retry()
        syncRoutes()
    }

    private func apply(_ setting: AppVolume, to key: String) {
        store[key] = setting
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].volume = setting.volume
            entries[index].isMuted = setting.isMuted
        }
        // Touching a slider gives a failed route, or a failed capture check, another chance.
        routes.clearFailures(for: key)
        capture.retry()
        syncRoutes()
    }

    private func clientsChanged() {
        let clients = monitor.clients
        identities = clients.mapValues { resolver.identity(for: $0) }
        resolver.forget(allBut: Set(clients.values.map(\.pid)))
        syncRoutes()
    }

    private func syncRoutes() {
        let apps = currentApps()
        if routesAudio, apps.contains(where: \.setting.needsRouting), capture.state != .allowed {
            capture.begin(on: output.deviceID)
        }
        let canRoute = routesAudio && capture.state == .allowed
        routes.sync(
            apps.map { app in
                RouteManager.Request(
                    key: app.key,
                    label: app.identity.name,
                    processObjectIDs: app.processObjectIDs,
                    outputDevice: output.deviceID,
                    gain: app.setting.gain,
                    isPlaying: app.isPlaying,
                    isWanted: canRoute && app.setting.needsRouting
                )
            }
        )
        updateBackgroundWork()
        rebuildEntries(from: apps)
    }

    private func currentApps() -> [AppAudio] {
        var clientsByKey: [String: [AudioClient]] = [:]
        var identityByKey: [String: AppIdentity] = [:]
        for client in monitor.clients.values {
            guard let identity = identities[client.objectID] else { continue }
            clientsByKey[identity.key, default: []].append(client)
            identityByKey[identity.key] = identity
        }
        return identityByKey.map { key, identity in
            AppAudio(identity: identity, clients: clientsByKey[key, default: []], setting: store[key])
        }
    }

    private func rebuildEntries(from apps: [AppAudio]) {
        guard !isDemo else { return }
        // Once an app has a row it keeps it until it quits, so pausing it or dragging it back to
        // 100% never pulls the row away in the middle of an adjustment.
        listedKeys.formIntersection(apps.map(\.key))
        let shown = apps.filter { $0.isPlaying || $0.setting.needsRouting || listedKeys.contains($0.key) }
        listedKeys.formUnion(shown.map(\.key))
        let rows = shown.map { app in
            MixerEntry(
                id: app.key,
                name: app.identity.name,
                icon: app.identity.icon,
                volume: app.setting.volume,
                isMuted: app.setting.isMuted,
                isPlaying: app.isPlaying
            )
        }
        let ordered = RowOrder.arrange(rows, keepingPlacesOf: isPanelVisible ? entries.map(\.id) : nil)
        if ordered != entries {
            entries = ordered
        }
        logRows(ordered)
    }

    private func logRows(_ rows: [MixerEntry]) {
        let summary = rows.map { $0.isPlaying ? "\($0.name) (playing)" : $0.name }
        guard summary != rowSummary else { return }
        rowSummary = summary
        let text = summary.isEmpty ? "none" : summary.joined(separator: ", ")
        log.notice("Rows: \(text, privacy: .public)")
    }

    private func outputDeviceChanged() {
        capture.outputDeviceChanged(to: output.deviceID)
        // Routes still on the old device are replaced by the next sync.
        syncRoutes()
    }

    private func systemDidWake() {
        Task { [weak self] in
            try? await Task.sleep(for: Timing.wakeRebuild)
            self?.routes.rebuildAll(reason: "woke from sleep")
        }
    }

    private func listenForServiceRestart() {
        restartListener = PropertyListener(.system, kAudioHardwarePropertyServiceRestarted) { [weak self] in
            self?.audioServiceRestarted()
        }
    }

    /// Takes every route and check down before the app exits. A process that dies with routes
    /// running leaves coreaudiod tearing them down for up to a minute, and a mixer launched
    /// meanwhile hangs on its first route.
    func shutDown() {
        heartbeat?.cancel()
        heartbeat = nil
        capture.shutDown()
        routes.shutDown()
        log.notice("Shut down")
    }

    /// coreaudiod restarted: every tap, device and listener the mixer had is gone, and their IDs may
    /// already belong to something else, so nothing old is touched.
    private func audioServiceRestarted() {
        log.notice("Audio service restarted, starting over")
        routes.abandonAll()
        capture.abandon()
        listenForServiceRestart()
        output.start()
        monitor.restart()
    }

    private func updateBackgroundWork() {
        let isBusy = !routes.isEmpty || capture.isRunning
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

        let needsHeartbeat = !routes.isEmpty || isPanelVisible
        if needsHeartbeat, heartbeat == nil {
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Timing.heartbeat)
                    guard !Task.isCancelled, let self else { return }
                    beat()
                }
            }
        } else if !needsHeartbeat {
            heartbeat?.cancel()
            heartbeat = nil
        }
    }

    private func beat() {
        monitor.refreshPlaying()
        routes.reportIncomingAudio()
    }
}
