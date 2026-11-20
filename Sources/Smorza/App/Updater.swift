import AppKit
import Observation
import Sparkle

/// In-app updates through Sparkle: automatic checks in the background, and "Check for Updates…" in
/// the panel. A build whose Info.plist still holds the placeholder key (a local build, or one made
/// before the release keys exist) never starts Sparkle, which cannot verify downloads without a key
/// and would report an error at every launch.
@MainActor
@Observable
final class Updater: NSObject {
    /// What Info.plist holds until `generate_keys` has made the real key (docs/RELEASING.md).
    static let placeholderKey = "REPLACE_WITH_YOUR_PUBLIC_ED_KEY"

    private(set) var isConfigured: Bool
    private(set) var canCheckForUpdates = false
    /// A background check found an update and left it for the panel to mention.
    private(set) var isUpdateWaiting = false
    /// Sparkle keeps this in the app's defaults; on until the user turns it off.
    private(set) var automaticallyChecks = true

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    override init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !key.isEmpty && key != Self.placeholderKey
        super.init()
    }

    func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    func checkForUpdates() {
        // A menu bar app is not the active app, so Sparkle's window would open behind the others.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecks = enabled
    }

    /// The button as a released build shows it, for `--snapshot-demo`. Sparkle is not started.
    func showDemo() {
        isConfigured = true
        canCheckForUpdates = true
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// A menu bar app has no Dock icon to bounce: an update found in the background waits in the
    /// panel instead of opening a window over whatever the user is doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Right after launch or after the Mac sat idle, Sparkle's own window is welcome.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in self.isUpdateWaiting = !handleShowingUpdate }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.isUpdateWaiting = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.isUpdateWaiting = false }
    }
}
