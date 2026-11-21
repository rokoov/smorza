import AppKit
import SwiftUI

/// The settings window, opened from the panel's gear or Command-comma.
@MainActor
final class SettingsWindow: NSObject {
    /// Taller settings scroll inside the window, which keeps to a small screen.
    private static let height: CGFloat = 620

    private let makeContent: () -> SettingsView
    private var window: NSWindow?

    init(content: @escaping () -> SettingsView) {
        makeContent = content
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: makeContent().frame(height: Self.height))
            let window = NSWindow(contentViewController: host)
            window.title = "Smorza Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // A menu bar app is not active, so the window would open behind the others.
        Activation.bringForward()
        window?.makeKeyAndOrderFront(nil)
        // AppKit focuses the first field, the shortcut recorder, which would then take every key
        // pressed, Command-W included, as a new shortcut.
        window?.makeFirstResponder(nil)
    }
}
