import MixerCore
import SwiftUI

/// The order of output devices: with switching on, the first connected one becomes the default
/// output and each device keeps its own volume.
struct OutputSettings: View {
    let model: MixerModel

    var body: some View {
        Section("Output") {
            Toggle(
                "Switch to the first connected device below",
                isOn: Binding(get: { model.outputPriority.isEnabled }, set: { model.setOutputSwitching($0) })
            )
            if model.outputPriority.isEnabled {
                Text("Each device also keeps its own volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let devices = model.outputPriority.devices
                ForEach(Array(devices.enumerated()), id: \.element.uid) { index, device in
                    OutputPriorityRow(
                        device: device,
                        connected: model.output.device(withUID: device.uid),
                        isFirst: index == 0,
                        isLast: index == devices.count - 1,
                        onMove: { model.moveOutputDevice(device.uid, by: $0) },
                        onForget: { model.forgetOutputDevice(device.uid) }
                    )
                }
            }
        }
    }
}
