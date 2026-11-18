import SwiftUI

/// Icon, name and level on top, the slider below, mute on the right. The output device uses the
/// same layout so every slider, level and mute button lines up in one column.
struct MixerRow<Icon: View>: View {
    let title: String
    let level: String
    let value: Double
    let isMuted: Bool
    let isEnabled: Bool
    let onChange: (Double) -> Void
    let onToggleMute: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(level)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                    .controlSize(.small)
                    .disabled(!isEnabled)
                    .opacity(isMuted ? 0.45 : 1)
            }
            MuteButton(isMuted: isMuted, volume: value, action: onToggleMute)
        }
        .frame(minHeight: PanelMetrics.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
