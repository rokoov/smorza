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

struct OutputDeviceRow: View {
    let device: OutputDevice
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    /// Concentric with the panel's rounded corners minus the row inset.
    private let cornerRadius: CGFloat = 8

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
                    .background(Circle().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                Text(device.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PanelMetrics.padding - 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isSelected)
        .accessibilityLabel(device.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
