import MixerCore
import SwiftUI

/// An app's row. A dimmed, grey icon means the app is quiet right now.
struct AppRow: View {
    let entry: MixerEntry
    let onVolume: (Double) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        MixerRow(
            title: entry.name,
            level: entry.isMuted ? "Muted" : "\(VolumeCurve.percent(entry.volume))%",
            value: entry.volume,
            isMuted: entry.isMuted,
            isEnabled: true,
            onChange: onVolume,
            onToggleMute: onToggleMute
        ) {
            Image(nsImage: entry.icon)
                .resizable()
                .interpolation(.high)
                .saturation(entry.isPlaying ? 1 : 0)
                .opacity(entry.isPlaying ? 1 : 0.6)
                .help(entry.isPlaying ? "Playing" : "Quiet right now")
        }
    }
}
