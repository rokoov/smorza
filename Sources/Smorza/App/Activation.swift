import AppKit

/// Brings Smorza to the front for a window the user asked for.
@MainActor
enum Activation {
    /// `NSApp.activate()` waits for the app in front to give way, and a click in the menu bar panel,
    /// which never takes focus from that app, does not count as using Smorza, so Settings would
    /// open behind it. The call from before macOS 14 still comes forward.
    static func bringForward() {
        unsafeBitCast(NSApp, to: LegacyActivation.self).activate(ignoringOtherApps: true)
    }
}

/// Reaches the deprecated call without the deprecation warning.
@objc private protocol LegacyActivation {
    @objc(activateIgnoringOtherApps:)
    func activate(ignoringOtherApps flag: Bool)
}
