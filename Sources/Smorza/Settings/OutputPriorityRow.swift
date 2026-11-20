import MixerCore
import SwiftUI

/// One device in the order, with buttons to move it. A device that is not connected can be forgotten
/// from its context menu.
struct OutputPriorityRow: View {
    let device: OutputPriority.Device
    /// The device as it is connected now, or nil while it is away.
    let connected: OutputDevice?
    let isFirst: Bool
    let isLast: Bool
    let onMove: (Int) -> Void
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connected?.symbolName ?? "hifispeaker")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(device.name)
                .foregroundStyle(connected == nil ? .secondary : .primary)
            if connected == nil {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                onMove(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(isFirst)
            .accessibilityLabel("Move \(device.name) up")
            Button {
                onMove(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(isLast)
            .accessibilityLabel("Move \(device.name) down")
        }
        .buttonStyle(.borderless)
        .contextMenu {
            if connected == nil {
                Button("Forget \(device.name)", action: onForget)
            }
        }
    }
}
