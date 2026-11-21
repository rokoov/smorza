import AppKit
import MixerCore
import SwiftUI

/// Opens the welcome window on the first launch, before macOS is asked for the permission, and
/// again from Settings. A Mac that already has Smorza's settings (an update) never sees it by itself.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private static let shownKey = "WelcomeShown"

    private var window: NSWindow?
    private weak var model: MixerModel?
    /// The app is quitting: AppKit closes the window then, which is not the user being done with it.
    var isQuitting = false

    /// True until the window has been closed once, and false for a Mac that had Smorza's settings
    /// before the window existed. Asked before Volume Mixer's settings are copied in: they bring no
    /// permission for the new name, so that Mac still has to see the window first.
    static func isFirstLaunch(defaults: UserDefaults = .standard) -> Bool {
        if let wasShown = defaults.object(forKey: shownKey) as? Bool {
            return !wasShown
        }
        return defaults.object(forKey: MixerSettingsStore.standardKey) == nil
    }

    func show(for model: MixerModel) {
        self.model = model
        // macOS asks for the permission only once the window explains it and the user continues.
        model.defersCaptureCheck = true
        // Quitting before the window is closed brings it back on the next launch.
        if UserDefaults.standard.object(forKey: Self.shownKey) == nil {
            UserDefaults.standard.set(false, forKey: Self.shownKey)
        }
        if window == nil {
            let host = NSHostingController(
                rootView: WelcomeView(model: model, onFinish: { [weak self] in self?.close() })
            )
            let window = NSWindow(contentViewController: host)
            window.title = String(localized: "Welcome to Smorza")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.collectionBehavior = WindowPlacement.behavior
            WindowPlacement.center(window)
            self.window = window
        }
        // Opened from Finder the app is in front; launched any other way, or after a click
        // elsewhere, NSApp.activate() would leave the window behind the app in front.
        Activation.bringForward()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isQuitting else { return }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        window = nil
        model?.endCaptureDeferral()
    }
}
