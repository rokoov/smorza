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
    private(set) var profiles: [Profile] = []
    /// The app playing solo, with every other app in the mixer muted.
    private(set) var solo: SoloSession?
    let output = SystemOutput()
    /// How far the sliders go: to 100%, or to 200% where boost is on.
    let volumeScale = ProFeatures.volumeScale
    let volumeKeys = VolumeKeys()
    /// Off only for the `--snapshot` previews, which must never touch anyone's audio.
    @ObservationIgnored var routesAudio = true

    private let capture = CaptureCheckController()
    private let routes = RouteManager()
    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let store = MixerSettingsStore()
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored private let hud = VolumeHUD()
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
        output.onDevicesChange = { [weak self] in self?.outputDevicesChanged() }
        capture.onFinish = { [weak self] in self?.syncRoutes() }
        routes.onRetry = { [weak self] in self?.syncRoutes() }
        routes.onRoutesChanged = { [weak self] in self?.updateBackgroundWork() }
        output.start()
        monitor.start()
        listenForServiceRestart()
        profilesChanged()
        volumeKeys.onKey = { [weak self] key, isFine in
            self?.handleVolumeKey(key, isFine: isFine)
        }
        volumeKeys.start()
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
        var setting = store.volume(for: key, on: outputDeviceUID(for: key))
        setting.volume = volumeScale.clamped(volume)
        apply(setting, to: key)
    }

    func toggleMute(for key: String) {
        // Muting by hand takes over from a solo, whose saved mutes no longer apply.
        endSolo(restoring: false)
        var setting = store.volume(for: key, on: outputDeviceUID(for: key))
        setting.isMuted.toggle()
        apply(setting, to: key)
    }

    /// Mutes every other app in the mixer and unmutes this one. Soloing it again, or quitting it,
    /// puts every other app's mute back as it was.
    func toggleSolo(for key: String) {
        guard solo?.key != key else {
            endSolo(restoring: true)
            return
        }
        endSolo(restoring: true)
        let session = SoloSession(
            key: key,
            mutesBefore: Dictionary(entries.map { ($0.id, $0.isMuted) }, uniquingKeysWith: { first, _ in first })
        )
        solo = session
        let name = entries.first { $0.id == key }?.name ?? key
        log.notice("Solo: \(name, privacy: .public)")
        setMutes(session.mutes)
    }

    /// Saves the mix as it is now: every app in the mixer with its volume and mute. A profile with the
    /// same name is replaced, so saving "Gaming" again updates it.
    func saveProfile(named name: String, mutesOtherApps: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = profiles.first { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        let profile = Profile(
            id: existing?.id ?? UUID(),
            name: trimmed,
            apps: currentMix(),
            mutesOtherApps: mutesOtherApps
        )
        store.saveProfile(profile)
        log.notice("Saved profile \(trimmed, privacy: .public)")
        profilesChanged()
    }

    func applyProfile(_ profile: Profile) {
        endSolo(restoring: false)
        for (key, setting) in profile.changes(from: currentMix()) {
            store.setVolume(setting, for: key, on: outputDeviceUID(for: key))
            routes.clearFailures(for: key)
        }
        capture.retry()
        let name = profile.name
        log.notice("Switched to profile \(name, privacy: .public)")
        syncRoutes()
    }

    func deleteProfile(_ profile: Profile) {
        store.deleteProfile(id: profile.id)
        profilesChanged()
    }

    /// Sends the app to `device`, or back to the system output with nil.
    func setOutputDevice(_ device: OutputDevice?, for key: String) {
        store.setOutputDevice(uid: device?.uid, name: device?.name, for: key)
        routes.clearFailures(for: key)
        syncRoutes()
    }

    func retryCaptureCheck() {
        capture.retry()
        syncRoutes()
    }

    private func apply(_ setting: AppVolume, to key: String) {
        store.setVolume(setting, for: key, on: outputDeviceUID(for: key))
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].volume = setting.volume
            entries[index].isMuted = setting.isMuted
        }
        // Touching a slider gives a failed route, or a failed capture check, another chance.
        routes.clearFailures(for: key)
        capture.retry()
        syncRoutes()
    }

    /// Control + a volume key changes the app in front, not the whole Mac, and shows the overlay.
    private func handleVolumeKey(_ key: VolumeKeyTap.Key, isFine: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let appKey = app.bundleIdentifier,
            appKey != Bundle.main.bundleIdentifier
        else { return }
        var setting = store.volume(for: appKey, on: outputDeviceUID(for: appKey))
        setting.volume = volumeScale.clamped(setting.volume)
        switch key {
        case .up:
            // Like the system volume, raising it also unmutes.
            setting.volume = volumeScale.stepped(setting.volume, by: 1, fine: isFine)
            setting.isMuted = false
        case .down:
            setting.volume = volumeScale.stepped(setting.volume, by: -1, fine: isFine)
        case .mute:
            endSolo(restoring: false)
            setting.isMuted.toggle()
        }
        apply(setting, to: appKey)
        hud.show(
            VolumeHUDView(
                name: app.localizedName ?? appKey,
                icon: app.icon ?? NSImage(),
                volume: setting.volume,
                isMuted: setting.isMuted,
                scale: volumeScale
            )
        )
    }

    /// Every app in the mixer with the volume and mute it has now.
    private func currentMix() -> [String: AppVolume] {
        Dictionary(
            entries.map { ($0.id, AppVolume(volume: $0.volume, isMuted: $0.isMuted)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The first nine profiles answer to Control-Option-1 to 9. Without Pro the saved profiles stay
    /// untouched but hidden, with no shortcuts.
    private func profilesChanged() {
        hotKeys.unregisterAll()
        guard ProFeatures.isProfilesEnabled else {
            profiles = []
            return
        }
        profiles = store.profiles
        var shortcuts = 0
        for (index, profile) in profiles.prefix(9).enumerated() {
            let isRegistered = hotKeys.registerControlOption(number: index + 1) { [weak self] in
                self?.applyProfile(profile)
            }
            shortcuts += isRegistered ? 1 : 0
        }
        if !profiles.isEmpty {
            log.notice("Profiles: \(self.profiles.count), with shortcuts: \(shortcuts)")
        }
    }

    private func endSolo(restoring: Bool) {
        guard let session = solo else { return }
        solo = nil
        if restoring {
            setMutes(session.mutesBefore)
        }
    }

    /// Sets several apps' mutes on the devices they play on now, then syncs once.
    private func setMutes(_ mutes: [String: Bool]) {
        for (key, isMuted) in mutes {
            let deviceUID = outputDeviceUID(for: key)
            var setting = store.volume(for: key, on: deviceUID)
            guard setting.isMuted != isMuted else { continue }
            setting.isMuted = isMuted
            store.setVolume(setting, for: key, on: deviceUID)
            routes.clearFailures(for: key)
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
        let apps = currentApps()
        if let solo, !apps.contains(where: { $0.key == solo.key }) {
            // The solo app quit; the others get their sound back.
            endSolo(restoring: true)
            return
        }
        // A device an app plays on for the first time gets its own copy of the app's last volume,
        // so a later change on another device leaves this one alone.
        for app in apps where !app.settings.isDefault {
            store.adoptVolume(for: app.key, on: app.outputDeviceUID)
        }
        if routesAudio, apps.contains(where: \.needsRoute), capture.state != .allowed {
            capture.begin(on: output.deviceID)
        }
        let canRoute = routesAudio && capture.state == .allowed
        routes.sync(
            apps.map { app in
                RouteManager.Request(
                    key: app.key,
                    label: app.identity.name,
                    processObjectIDs: app.processObjectIDs,
                    outputDevice: app.outputDeviceID,
                    gain: app.volume.gain,
                    isPlaying: app.isPlaying,
                    isWanted: canRoute && app.needsRoute
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
        let connected = Set(output.devices.map(\.uid))
        return identityByKey.map { key, identity in
            let settings = store.settings(for: key)
            let deviceUID = settings.outputDeviceUID(systemOutputUID: output.deviceUID, connectedUIDs: connected)
            let device = output.device(withUID: deviceUID)
            var volume = settings.volume(on: deviceUID)
            volume.volume = volumeScale.clamped(volume.volume)
            return AppAudio(
                identity: identity,
                clients: clientsByKey[key, default: []],
                settings: settings,
                volume: volume,
                chosenDevice: settings.outputDeviceUID.flatMap(output.device(withUID:)),
                outputDeviceID: device?.id ?? output.deviceID,
                outputDeviceUID: deviceUID,
                outputSymbol: device?.symbolName ?? output.symbolName,
                needsRoute: settings.needsRoute(
                    systemOutputUID: output.deviceUID,
                    connectedUIDs: connected,
                    scale: volumeScale
                )
            )
        }
    }

    /// Where the app plays now: its picked device while connected, otherwise the system output.
    private func outputDeviceUID(for key: String) -> String {
        store.settings(for: key).outputDeviceUID(
            systemOutputUID: output.deviceUID,
            connectedUIDs: Set(output.devices.map(\.uid))
        )
    }

    private func rebuildEntries(from apps: [AppAudio]) {
        guard !isDemo else { return }
        // Once an app has a row it keeps it until it quits, so pausing it or dragging it back to
        // 100% never pulls the row away in the middle of an adjustment.
        listedKeys.formIntersection(apps.map(\.key))
        let shown = apps.filter { $0.isPlaying || $0.needsRoute || listedKeys.contains($0.key) }
        listedKeys.formUnion(shown.map(\.key))
        let rows = shown.map { app in
            MixerEntry(
                id: app.key,
                name: app.identity.name,
                icon: app.identity.icon,
                volume: app.volume.volume,
                isMuted: app.volume.isMuted,
                isPlaying: app.isPlaying,
                outputDeviceUID: app.settings.outputDeviceUID,
                outputDeviceName: app.settings.outputDeviceName,
                outputSymbol: app.outputSymbol,
                isOutputConnected: app.settings.outputDeviceUID == nil || app.chosenDevice != nil,
                isSolo: app.key == solo?.key
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

    /// A device came or went: apps sent to it move there or fall back to the system output. Only
    /// routes whose device changed are rebuilt, each new one starting before the old one goes.
    private func outputDevicesChanged() {
        log.notice("Output devices changed: \(self.output.devices.count) connected")
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
