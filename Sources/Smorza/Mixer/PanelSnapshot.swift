import AppKit
import SwiftUI

/// `Smorza --snapshot <dir>` renders the panel with live data in light and dark, routing off.
/// `--snapshot-demo <dir>` does the same with `DemoContent`, for the README.
@MainActor
enum PanelSnapshot {
    /// Room around the panel for its shadow.
    private static let margin: CGFloat = 28
    private static let cornerRadius: CGFloat = 14
    /// Long enough for SwiftUI to lay out and for app icons to load.
    private static let settleTime: TimeInterval = 0.5

    static func write(to directory: String, demo: Bool) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = MixerModel()
        let updater = Updater()
        model.routesAudio = false
        if demo {
            model.showDemo(DemoContent.entries)
            model.meters.showDemo(DemoContent.meterBars)
            updater.showDemo()
            model.output.showDemo(
                name: DemoContent.devices[0].name,
                symbolName: DemoContent.devices[0].symbolName,
                volume: DemoContent.outputVolume,
                devices: DemoContent.devices
            )
        } else {
            model.start()
        }

        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            write(
                render(framed(MixerPanel(model: model, updater: updater)), appearance: appearance),
                as: "panel-\(name)",
                in: directory
            )
            if demo {
                write(render(DemoContent.hud.padding(margin), appearance: appearance), as: "hud-\(name)", in: directory)
                write(
                    render(SettingsView(model: model, updater: updater), appearance: appearance),
                    as: "settings-\(name)",
                    in: directory
                )
            }
        }
    }

    private static func framed(_ panel: MixerPanel) -> some View {
        let corners = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return
            panel
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(corners)
            .overlay(corners.strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            .padding(margin)
    }

    private static func write(_ png: Data?, as name: String, in directory: String) {
        guard let png else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("Wrote \(url.path)")
    }

    private static func render(_ view: some View, appearance: NSAppearance) -> Data? {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settleTime))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        window.setContentSize(host.frame.size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
