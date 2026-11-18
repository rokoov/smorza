import MixerCore
import SwiftUI

/// The current output device's own volume and mute, laid out like an app row.
struct OutputRow: View {
    let output: SystemOutput

    var body: some View {
        MixerRow(
            title: output.name,
            level: output.canSetVolume
                ? (output.isMuted ? "Muted" : "\(VolumeCurve.percent(output.volume))%") : "Fixed",
            value: output.volume,
            isMuted: output.isMuted,
            isEnabled: output.canSetVolume,
            onChange: { output.setVolume($0) },
            onToggleMute: { output.setMuted(!output.isMuted) }
        ) {
            // A quiet plate: the apps below are what the panel is for.
            Image(systemName: output.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
                .background(.quaternary, in: Circle())
        }
        .accessibilityLabel("Output volume, \(output.name)")
    }
}
