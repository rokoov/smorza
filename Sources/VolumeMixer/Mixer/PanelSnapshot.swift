import AppKit
import SwiftUI

/// `VolumeMixer --snapshot <dir>` renders the panel with live data in light and dark, routing off.
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
        model.routesAudio = false
        if demo {
            model.showDemo(DemoContent.entries)
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
            guard let appearance = NSAppearance(named: appearanceName),
                let png = render(MixerPanel(model: model), appearance: appearance)
            else { continue }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("panel-\(name).png")
            try? png.write(to: url)
            print("Wrote \(url.path)")
        }
    }

    private static func render(_ panel: MixerPanel, appearance: NSAppearance) -> Data? {
        let corners = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let framed =
            panel
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(corners)
            .overlay(corners.strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            .padding(margin)
        let host = NSHostingView(rootView: framed)
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
