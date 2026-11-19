import SwiftUI

/// The choices for where one app plays: the system default, or any output device, with a checkmark
/// on the current one. Used by the row's output button and by its context menu.
struct AppOutputChoices: View {
    let entry: MixerEntry
    let devices: [OutputDevice]
    let systemOutputName: String
    let onChoose: (OutputDevice?) -> Void

    var body: some View {
        Toggle("System Default (\(systemOutputName))", isOn: chosen(nil))
        Divider()
        ForEach(devices) { device in
            Toggle(device.name, isOn: chosen(device))
        }
        if !entry.isOutputConnected {
            Divider()
            Text("\(entry.outputDeviceName ?? "The chosen device") is not connected")
        }
    }

    /// A menu checkmark bound to whether `device` is the app's pick; choosing it sends the app there.
    private func chosen(_ device: OutputDevice?) -> Binding<Bool> {
        Binding(
            get: { entry.outputDeviceUID == device?.uid },
            set: { _ in onChoose(device) }
        )
    }
}
