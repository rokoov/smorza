import ApplicationServices
import Foundation
import Observation

/// The "Control + volume keys change the app in front" option: remembers whether it is on, asks for
/// the Accessibility permission the event tap needs, and runs the tap once it is granted.
@MainActor
@Observable
final class VolumeKeys {
    /// How often the permission is checked again while the option is on but not yet allowed.
    private static let trustPollInterval: Duration = .seconds(2)
    nonisolated static let enabledKey = "VolumeKeysEnabled"

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: VolumeKeys.enabledKey)
    private(set) var isTrusted = AXIsProcessTrusted()
    /// Called on the main thread for every press of a caught key.
    @ObservationIgnored var onKey: ((_ key: VolumeKeyTap.Key, _ isFine: Bool) -> Void)?

    @ObservationIgnored private var tap: VolumeKeyTap?
    @ObservationIgnored private var trustPoll: Task<Void, Never>?

    func start() {
        if isEnabled {
            activate(askingForPermission: false)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            activate(askingForPermission: true)
        } else {
            deactivate()
        }
    }

    private func activate(askingForPermission: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): askingForPermission] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        guard isTrusted else {
            waitForPermission()
            return
        }
        installTap()
    }

    private func deactivate() {
        trustPoll?.cancel()
        trustPoll = nil
        tap?.invalidate()
        tap = nil
    }

    private func installTap() {
        guard tap == nil else { return }
        tap = VolumeKeyTap { [weak self] key, isFine in
            self?.onKey?(key, isFine)
        }
        log.notice("Volume keys \(self.tap == nil ? "could not be caught" : "caught", privacy: .public)")
    }

    private func waitForPermission() {
        guard trustPoll == nil else { return }
        trustPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.trustPollInterval)
                guard let self, isEnabled else { return }
                guard AXIsProcessTrusted() else { continue }
                isTrusted = true
                trustPoll = nil
                installTap()
                return
            }
        }
    }
}
