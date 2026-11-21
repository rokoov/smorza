import AppKit
import CoreAudio
import Foundation
import KeyboardShortcuts
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
        /// How often the level meters read the routes while the panel is open.
        static let meterUpdate: Duration = .milliseconds(50)
        /// The same with Reduce Motion on: a calm reading twice a second instead of a moving bar.
        static let calmMeterUpdate: Duration = .milliseconds(500)
    }

    private(set) var entries: [MixerEntry] = []
    private(set) var profiles: [Profile] = []
    /// The app playing solo, with every other app in the mixer muted.
    private(set) var solo: SoloSession?
    /// Every app in the mixer muted by Mute All.
    private(set) var muteAll: MuteAllSession?
    /// The user's order of output devices, for automatic switching.
    private(set) var outputPriority = OutputPriority()
    let output = SystemOutput()
    /// How far the sliders go: to 100%, or to 200% where boost is on.
    let volumeScale = ProFeatures.volumeScale
    let volumeKeys = VolumeKeys()
    let meters = MeterLevels()
    /// Each app's colour, for sliders tinted with it.
    @ObservationIgnored let appTints = AppTints()
    /// Off only for the `--snapshot` previews, which must never touch anyone's audio.
    @ObservationIgnored var routesAudio = true
    /// While the welcome window explains the permission, routes wait, so macOS does not ask first.
    @ObservationIgnored var defersCaptureCheck = false

    private let capture = CaptureCheckController()
    private let routes = RouteManager()
    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let store = MixerSettingsStore()
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored private let hud = VolumeHUD()
    @ObservationIgnored private var identities: [AudioObjectID: AppIdentity] = [:]
    @ObservationIgnored private var listedKeys: Set<String> = []
    /// When each app was last seen playing, for the order of the quiet rows.
    @ObservationIgnored private var lastPlayed: [String: Date] = [:]
    /// False until the first output device is read, so starting up shows no overlay.
    @ObservationIgnored private var hasLoadedOutput = false
    @ObservationIgnored private var rowSummary: [String] = []
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var isDemo = false
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var meterLoop: Task<Void, Never>?
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
        output.onLevelsChange = { [weak self] in self?.outputLevelsChanged() }
        outputPriority = store.outputPriority
        capture.onFinish = { [weak self] in self?.syncRoutes() }
        routes.onRetry = { [weak self] in self?.syncRoutes() }
        routes.onRoutesChanged = { [weak self] in self?.updateBackgroundWork() }
        output.start()
        hasLoadedOutput = true
        applyOutputPriority()
        monitor.start()
        listenForServiceRestart()
        profilesChanged()
        volumeKeys.onKey = { [weak self] key, isPressed, isFine in
            self?.handleVolumeKey(key, isPressed: isPressed, isFine: isFine) ?? false
        }
        volumeKeys.start()
        KeyboardShortcuts.onKeyUp(for: .muteAll) { [weak self] in
            self?.toggleMuteAll()
        }
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
        meters.clear()
        rebuildEntries(from: currentApps())
        updateBackgroundWork()
        log.notice("Panel closed")
    }

    func setVolume(_ volume: Double, for key: String) {
        var setting = store.volume(for: key, on: outputDeviceUID(for: key))
        setting.volume = volumeScale.clamped(volume)
        apply(setting, to: key)
    }

    /// Moves an app's slider by `change` of its length, for scrolling over its row.
    func nudgeVolume(of key: String, byPosition change: Double) {
        let current = volumeScale.clamped(store.volume(for: key, on: outputDeviceUID(for: key)).volume)
        let position = min(max(volumeScale.position(of: current) + change, 0), 1)
        setVolume(volumeScale.volume(atPosition: position), for: key)
    }

    /// Mutes or unmutes an app, for the Shortcuts actions.
    func setMuted(_ isMuted: Bool, for key: String) {
        guard store.volume(for: key, on: outputDeviceUID(for: key)).isMuted != isMuted else { return }
        toggleMute(for: key)
    }

    /// Mute All on or off, for the Shortcuts actions.
    func setAllMuted(_ isMuted: Bool) {
        guard isMuted != (muteAll != nil) else { return }
        toggleMuteAll()
    }

    /// Running apps with a bundle, for the app picker of the Shortcuts actions.
    func shortcutApps() -> [AppIdentity] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let key = app.bundleIdentifier else { return nil }
                return AppIdentity(key: key, name: app.localizedName ?? key, icon: app.icon ?? NSImage())
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// An app a shortcut names, running or only installed.
    func shortcutApp(id: String) -> AppIdentity? {
        shortcutApps().first { $0.key == id } ?? resolver.identity(forBundleIdentifier: id)
    }

    /// Keeps an app's row while it is quiet or not running, or lets it go again.
    func togglePin(for key: String) {
        let isPinned = !store.settings(for: key).isPinned
        store.setPinned(isPinned, for: key)
        let name = entries.first { $0.id == key }?.name ?? key
        log.notice("\(isPinned ? "Pinned" : "Unpinned", privacy: .public) \(name, privacy: .public)")
        rebuildEntries(from: currentApps())
    }

    func toggleMute(for key: String) {
        // Muting by hand takes over from a solo or Mute All, whose saved mutes no longer apply.
        endSolo(restoring: false)
        muteAll = nil
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
        endMuteAll()
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

    /// Mutes every app in the mixer, or gives each one its mute from before. Shown in the overlay,
    /// since the shortcut works with the panel closed.
    func toggleMuteAll() {
        if muteAll != nil {
            endMuteAll()
        } else {
            endSolo(restoring: true)
            let session = MuteAllSession(
                mutesBefore: Dictionary(entries.map { ($0.id, $0.isMuted) }, uniquingKeysWith: { first, _ in first })
            )
            muteAll = session
            log.notice("Muted all apps")
            setMutes(session.mutes)
        }
        hud.show(
            VolumeHUDView(
                name: "All apps",
                icon: NSApp.applicationIconImage ?? NSImage(),
                volume: 0,
                isMuted: muteAll != nil,
                scale: volumeScale,
                status: muteAll != nil ? "Muted" : "Back as they were",
                showsLevel: false
            )
        )
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
        muteAll = nil
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

    /// Turns automatic switching to the first connected device of the user's order on or off.
    func setOutputSwitching(_ isEnabled: Bool) {
        outputPriority.isEnabled = isEnabled
        if isEnabled {
            rememberOutputVolume()
        }
        store.setOutputPriority(outputPriority)
        applyOutputPriority()
    }

    /// Moves a device up (negative) or down (positive) the user's order.
    func moveOutputDevice(_ uid: String, by offset: Int) {
        outputPriority.move(uid, by: offset)
        store.setOutputPriority(outputPriority)
        applyOutputPriority()
    }

    func forgetOutputDevice(_ uid: String) {
        outputPriority.forget(uid)
        store.setOutputPriority(outputPriority)
    }

    /// Starts the capture check, which makes macOS ask for the permission the first time.
    func requestCapturePermission() {
        defersCaptureCheck = false
        capture.retry()
        capture.begin(on: output.deviceID)
    }

    /// The welcome window closed: routes no longer wait for it.
    func endCaptureDeferral() {
        guard defersCaptureCheck else { return }
        defersCaptureCheck = false
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

    /// A volume key changes the app in front, not the whole Mac, and shows the overlay. With no app
    /// in front that the mixer could change (this app, or one with no bundle), the system keeps it.
    private func handleVolumeKey(_ key: VolumeKeyTap.Key, isPressed: Bool, isFine: Bool) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let appKey = app.bundleIdentifier,
            appKey != Bundle.main.bundleIdentifier
        else { return false }
        // The release only has to be kept from the system, like its press.
        guard isPressed else { return true }
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
            muteAll = nil
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
        return true
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

    private func endMuteAll() {
        guard let session = muteAll else { return }
        muteAll = nil
        log.notice("Unmuted all apps")
        setMutes(session.mutesBefore)
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
        if routesAudio, !defersCaptureCheck, apps.contains(where: \.needsRoute), capture.state != .allowed {
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
        let now = Date()
        for app in apps where app.isPlaying {
            lastPlayed[app.key] = now
        }
        listedKeys.formIntersection(apps.map(\.key))
        let pinned = Set(store.pinnedApps)
        let shown = apps.filter {
            $0.isPlaying || $0.needsRoute || listedKeys.contains($0.key) || pinned.contains($0.key)
        }
        listedKeys.formUnion(shown.map(\.key))
        let running = shown.map { app in
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
                isSolo: app.key == solo?.key,
                isPinned: pinned.contains(app.key),
                isRouted: app.needsRoute
            )
        }
        let rows = running + pinnedRows(for: pinned.subtracting(apps.map(\.key)))
        let ordered = RowOrder.arrange(
            rows,
            lastPlayed: lastPlayed,
            keepingPlacesOf: isPanelVisible ? entries.map(\.id) : nil
        )
        if ordered != entries {
            entries = ordered
        }
        logRows(ordered)
    }

    /// Rows for pinned apps that are not running, from their saved settings, so they can be set
    /// before they start.
    private func pinnedRows(for keys: Set<String>) -> [MixerEntry] {
        let connected = Set(output.devices.map(\.uid))
        return keys.compactMap { key in
            guard let identity = resolver.identity(forBundleIdentifier: key) else { return nil }
            let settings = store.settings(for: key)
            let deviceUID = settings.outputDeviceUID(systemOutputUID: output.deviceUID, connectedUIDs: connected)
            var volume = settings.volume(on: deviceUID)
            volume.volume = volumeScale.clamped(volume.volume)
            return MixerEntry(
                id: key,
                name: identity.name,
                icon: identity.icon,
                volume: volume.volume,
                isMuted: volume.isMuted,
                isPlaying: false,
                outputDeviceUID: settings.outputDeviceUID,
                outputDeviceName: settings.outputDeviceName,
                outputSymbol: output.device(withUID: deviceUID)?.symbolName ?? output.symbolName,
                isOutputConnected: settings.outputDeviceUID.map(connected.contains) ?? true,
                isPinned: true,
                isRunning: false
            )
        }
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
        // Each device keeps its own volume, for devices that do not keep it themselves.
        if outputPriority.isEnabled, output.canSetVolume,
            let volume = outputPriority.volumes[output.deviceUID], abs(volume - output.volume) > 0.005
        {
            output.setVolume(volume)
        }
        // In the panel the switch is in plain sight; elsewhere the overlay says where sound went.
        if hasLoadedOutput, !isPanelVisible {
            showOutputOverlay()
        }
        // Routes still on the old device are replaced by the next sync.
        syncRoutes()
    }

    /// A device came or went: apps sent to it move there or fall back to the system output. Only
    /// routes whose device changed are rebuilt, each new one starting before the old one goes.
    private func outputDevicesChanged() {
        log.notice("Output devices changed: \(self.output.devices.count) connected")
        let seen = output.devices.map { OutputPriority.Device(uid: $0.uid, name: $0.name) }
        if outputPriority.learn(seen) {
            store.setOutputPriority(outputPriority)
        }
        applyOutputPriority()
        syncRoutes()
    }

    /// Makes the first connected device of the user's order the default output, when it is not.
    /// Only a device coming or going, or a change to the order, switches: a device the user picks
    /// by hand stays until then.
    private func applyOutputPriority() {
        // The device list loads before the current output, and snapshots never change the output.
        guard hasLoadedOutput, routesAudio,
            let uid = outputPriority.preferredDevice(among: Set(output.devices.map(\.uid))),
            uid != output.deviceUID,
            let device = output.device(withUID: uid)
        else { return }
        log.notice("Output priority: switching to \(device.name, privacy: .public)")
        output.select(device)
    }

    private func outputLevelsChanged() {
        if outputPriority.isEnabled {
            rememberOutputVolume()
        }
    }

    private func rememberOutputVolume() {
        guard !output.deviceUID.isEmpty, output.canSetVolume else { return }
        outputPriority.volumes[output.deviceUID] = output.volume
        store.setOutputPriority(outputPriority)
    }

    private func showOutputOverlay() {
        let icon = NSImage(systemSymbolName: output.symbolName, accessibilityDescription: nil) ?? NSImage()
        hud.show(
            VolumeHUDView(
                name: output.name,
                icon: icon,
                volume: output.volume,
                isMuted: output.isMuted,
                scale: .standard,
                status: output.canSetVolume ? nil : "Fixed volume",
                showsLevel: output.canSetVolume
            )
        )
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

    /// Puts a report of what the mixer sees and does on the clipboard, for a bug report.
    func copyDiagnostics() async {
        let report = await Diagnostics.report(mixer: diagnosticSummary())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    private func diagnosticSummary() -> [String] {
        var lines = ["Capture check: \(capture.state)"]
        if let routingError {
            lines.append("Last error: \(routingError)")
        }
        lines.append("Output devices:")
        for device in output.devices {
            let marker = device.id == output.deviceID ? "*" : " "
            let inputs = device.id.streamCount(scope: kAudioObjectPropertyScopeInput)
            lines.append("  \(marker) \(device.name) [\(device.uid)], \(inputs) input streams")
        }
        let apps = currentApps()
        let quiet = apps.filter { !$0.isPlaying && !$0.needsRoute && $0.settings.isDefault }
        lines.append("Apps (\(quiet.count) more idle at 100% on the default output):")
        for app in apps where !quiet.contains(where: { $0.key == app.key }) {
            let level = app.volume.isMuted ? "muted" : "\(VolumeCurve.percent(app.volume.volume))%"
            let state = app.isPlaying ? "playing" : "idle"
            let route = app.needsRoute ? ", routed" : ""
            lines.append("  \(app.identity.name) [\(app.key)]: \(state), \(level) on \(app.outputDeviceUID)\(route)")
        }
        lines.append("Routes:")
        lines += routes.summary().map { "  \($0)" }
        return lines
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

        // Meters only matter while someone looks at them, and only routes have levels to show.
        let needsMeters = isPanelVisible && !routes.isEmpty
        if needsMeters, meterLoop == nil {
            meterLoop = Task { [weak self] in
                while !Task.isCancelled {
                    let isCalm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    try? await Task.sleep(for: isCalm ? Timing.calmMeterUpdate : Timing.meterUpdate)
                    guard !Task.isCancelled, let self else { return }
                    meters.update(with: routes.sampleLevels(), isSmoothed: !isCalm)
                }
            }
        } else if !needsMeters {
            meterLoop?.cancel()
            meterLoop = nil
            meters.clear()
        }
    }

    private func beat() {
        monitor.refreshPlaying()
        // While the panel is open the meters read the routes; otherwise this only logs first audio.
        if meterLoop == nil {
            _ = routes.sampleLevels()
        }
    }
}
