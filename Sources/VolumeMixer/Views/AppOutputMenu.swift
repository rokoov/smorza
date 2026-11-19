import SwiftUI

/// The output button of an app row. It shows the device only while the app has one of its own, so
/// rows on the system default stay clean; on those it appears while the pointer is over the row.
struct AppOutputMenu: View {
    let entry: MixerEntry
    let devices: [OutputDevice]
    let systemOutputName: String
    /// The row is under the pointer, so the button shows even on the system default.
    let isRevealed: Bool
    let onChoose: (OutputDevice?) -> Void

    var body: some View {
        Menu {
            AppOutputChoices(entry: entry, devices: devices, systemOutputName: systemOutputName, onChoose: onChoose)
        } label: {
            // A plain button style lets SwiftUI draw the label, so the tint shows; a borderless
            // menu draws it through AppKit, which ignores the style.
            Image(systemName: entry.outputSymbol)
                .foregroundStyle(iconStyle)
                .opacity(hasOwnDevice || isRevealed ? 1 : 0)
                .frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
        .accessibilityLabel("Output for \(entry.name)")
        .accessibilityValue(entry.outputDeviceName ?? "System Default")
    }

    private var hasOwnDevice: Bool { entry.outputDeviceUID != nil }

    /// Tinted on its own device; orange while that device is away and the app plays on the default.
    private var iconStyle: AnyShapeStyle {
        guard hasOwnDevice else { return AnyShapeStyle(.tertiary) }
        return entry.isOutputConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange)
    }

    private var helpText: String {
        guard hasOwnDevice else { return "Plays on the system default. Click to send it elsewhere." }
        let name = entry.outputDeviceName ?? "its own device"
        return entry.isOutputConnected ? "Plays on \(name)" : "\(name) is not connected; plays on the system default"
    }
}
