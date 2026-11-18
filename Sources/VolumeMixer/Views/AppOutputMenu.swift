import SwiftUI

/// Picks where one app plays: the system output, or a device of its own. The icon is the device the
/// app plays on now, tinted while the app has a device of its own.
struct AppOutputMenu: View {
    let entry: MixerEntry
    let devices: [OutputDevice]
    let systemOutputName: String
    let onChoose: (OutputDevice?) -> Void

    var body: some View {
        Menu {
            Toggle("System Output (\(systemOutputName))", isOn: chosen(nil))
            Divider()
            ForEach(devices) { device in
                Toggle(device.name, isOn: chosen(device))
            }
            if !entry.isOutputConnected {
                Divider()
                Text("\(entry.outputDeviceName ?? "The chosen device") is not connected")
            }
        } label: {
            // A plain button style lets SwiftUI draw the label, so the tint shows; a borderless
            // menu draws it through AppKit, which ignores the style.
            Image(systemName: entry.outputSymbol)
                .foregroundStyle(entry.outputDeviceUID == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
        .accessibilityLabel("Output for \(entry.name)")
    }

    private var helpText: String {
        guard entry.outputDeviceUID != nil else { return "Plays on the system output" }
        let name = entry.outputDeviceName ?? "its own device"
        return entry.isOutputConnected ? "Plays on \(name)" : "\(name) is not connected; plays on the system output"
    }

    /// A menu checkmark bound to whether `device` is the app's pick; choosing it sends the app there.
    private func chosen(_ device: OutputDevice?) -> Binding<Bool> {
        Binding(
            get: { entry.outputDeviceUID == device?.uid },
            set: { _ in onChoose(device) }
        )
    }
}
