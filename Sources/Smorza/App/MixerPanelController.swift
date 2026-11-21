import AppKit
import SwiftUI

/// The menu bar icon and the panel it opens. The panel is AppKit's own rather than a SwiftUI
/// MenuBarExtra, which code cannot open: here the icon, a shortcut and smorza://open all can, also
/// over a full-screen app.
@MainActor
final class MixerPanelController: NSObject, NSWindowDelegate {
    /// Space between the menu bar and the panel, and between the panel and the screen's edges.
    private static let margin: CGFloat = 6
    private static let cornerRadius: CGFloat = 16

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: PanelWindow
    private let host: PanelHostingView
    private var clickMonitor: Any?
    /// Told when the panel opens, before it shows, and after it closes.
    var onVisibilityChange: ((Bool) -> Void)?

    var isShown: Bool { panel.isVisible }

    init(content: some View) {
        host = PanelHostingView(rootView: AnyView(content))
        panel = PanelWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.contentView = Self.background(holding: host)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        host.onSizeChange = { [weak self] in self?.fitToContent() }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        setIcon(symbolName: "slider.horizontal.3")
    }

    func setIcon(symbolName: String) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Smorza")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard !isShown else { return }
        // Rows settle before the panel shows, and then hold still until it closes.
        onVisibilityChange?(true)
        position()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        // A click anywhere else, in any app, closes the panel as it does a menu.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere() }
        }
    }

    func close() {
        guard isShown else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        onVisibilityChange?(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func clickedElsewhere() {
        // The menu bar shows the icon for this app, so its click arrives here too, ahead of the
        // icon's own action, which closes the panel by itself.
        if let iconFrame = statusItem.button?.window?.frame, iconFrame.contains(NSEvent.mouseLocation) {
            return
        }
        close()
    }

    @objc private func iconClicked() {
        toggle()
    }

    /// Under the icon on the screen the pointer is on, or at the top right of that screen when the
    /// icon is elsewhere or its menu bar is hidden, as over a full-screen app.
    private func position() {
        let size = host.fittingSize
        let iconWindow = statusItem.button?.window
        let pointer = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                ?? iconWindow?.screen ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        var top = visible.maxY - Self.margin
        var left = visible.maxX - size.width - Self.margin
        if let iconFrame = iconWindow?.frame, iconWindow?.isVisible == true,
            screen.frame.minX...screen.frame.maxX ~= iconFrame.midX
        {
            top = min(iconFrame.minY - Self.margin, top)
            left = iconFrame.midX - size.width / 2
        }
        left = min(max(left, visible.minX + Self.margin), visible.maxX - size.width - Self.margin)
        panel.setFrame(NSRect(x: left, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Rows come and go while the panel is open; it grows or shrinks downwards from the menu bar.
    private func fitToContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, isShown else { return }
            let size = host.fittingSize
            let frame = panel.frame
            guard size != frame.size else { return }
            panel.setFrame(
                NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                display: true
            )
        }
    }

    /// Liquid Glass on macOS 26 and later, the panel material before.
    private static func background(holding content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }
}

/// A panel that takes keyboard focus without making the app active, like a menu, and closes on
/// Escape.
private final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Tells the controller when the panel's content wants another size.
private final class PanelHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}
