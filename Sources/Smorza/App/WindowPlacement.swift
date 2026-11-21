import AppKit

/// Puts Smorza's windows where the user is. A menu bar app has no Space of its own, and a window
/// left on another Space, or under a full-screen app, would open where nobody sees it.
@MainActor
enum WindowPlacement {
    /// Follows the user to the Space in front, also a full-screen app's.
    static let behavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    /// Centres the window a little above the middle of the screen the pointer is on, as `center()`
    /// does on the main screen.
    static func center(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.midX - size.width / 2
        let y = min(visible.midY - size.height / 2 + visible.height / 8, visible.maxY - size.height)
        window.setFrameOrigin(NSPoint(x: x, y: max(y, visible.minY)))
    }
}
