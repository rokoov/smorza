import AppKit
import SwiftUI

/// The small overlay that answers a volume key: which app changed and where it is now. It sits under
/// the menu bar at the right, near the mixer's icon, and fades after a moment.
@MainActor
final class VolumeHUD {
    /// How long the overlay stays after the last key press.
    private static let visibleTime: Duration = .milliseconds(1_400)
    private static let fadeTime: TimeInterval = 0.25
    /// Gap to the menu bar and the screen's right edge, in points.
    private static let margin: CGFloat = 12

    private var panel: NSPanel?
    private var host: NSHostingView<VolumeHUDView>?
    private var hideTask: Task<Void, Never>?

    func show(_ content: VolumeHUDView) {
        let panel = panel ?? makePanel(with: content)
        host?.rootView = content
        if let host {
            panel.setContentSize(host.fittingSize)
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.maxX - panel.frame.width - Self.margin,
                    y: frame.maxY - panel.frame.height - Self.margin
                )
            )
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleTime)
            guard !Task.isCancelled, let self else { return }
            hide()
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.fadeTime
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func makePanel(with content: VolumeHUDView) -> NSPanel {
        let host = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        self.host = host
        return panel
    }
}
