import SwiftUI

/// The output list, laid out like the Sound module in Control Center: one row per device, the
/// current one filled with the accent colour.
struct OutputPicker: View {
    let output: SystemOutput

    /// Rows sit this far in from the panel edge, so their icons line up with the app icons above.
    private let inset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Output")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, PanelMetrics.padding)
                .padding(.bottom, 2)
            VStack(spacing: 2) {
                ForEach(output.devices) { device in
                    OutputDeviceRow(device: device, isSelected: device.id == output.deviceID) {
                        output.select(device)
                    }
                }
            }
            .padding(.horizontal, inset)
        }
        .padding(.vertical, 10)
    }
}
