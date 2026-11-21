import AppKit
import MixerCore
import SwiftUI

/// Opens the welcome window on the first launch, before macOS is asked for the permission, and
/// again from Settings. A Mac that already has settings (an update) never sees it by itself.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private static let shownKey = "WelcomeShown"

    private var window: NSWindow?
    private weak var model: MixerModel?

    /// True for a first launch: no settings yet and the window never shown.
    var isFirstLaunch: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.shownKey) { return false }
        if defaults.object(forKey: MixerSettingsStore.standardKey) != nil {
            defaults.set(true, forKey: Self.shownKey)
            return false
        }
        return true
    }

    func show(for model: MixerModel) {
        self.model = model
        // macOS asks for the permission only once the window explains it and the user continues.
        model.defersCaptureCheck = true
        if window == nil {
            let host = NSHostingController(
                rootView: WelcomeView(model: model, onFinish: { [weak self] in self?.close() })
            )
            let window = NSWindow(contentViewController: host)
            window.title = String(localized: "Welcome to Smorza")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        window = nil
        model?.endCaptureDeferral()
    }
}
