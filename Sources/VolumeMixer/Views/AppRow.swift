import MixerCore
import SwiftUI

/// An app's row. A dimmed, grey icon means the app is quiet right now; an orange level means boost.
struct AppRow: View {
    let entry: MixerEntry
    let devices: [OutputDevice]
    let systemOutputName: String
    let onVolume: (Double) -> Void
    let onToggleMute: () -> Void
    let onChooseOutput: (OutputDevice?) -> Void

    var body: some View {
        MixerRow(
            title: entry.name,
            level: entry.isMuted ? "Muted" : "\(VolumeCurve.percent(entry.volume))%",
            position: VolumeCurve.position(of: entry.volume),
            volume: entry.volume,
            unityMark: VolumeCurve.unityPosition,
            isBoosted: entry.isBoosted && !entry.isMuted,
            isMuted: entry.isMuted,
            isEnabled: true,
            onChange: setPosition,
            onToggleMute: onToggleMute,
            accessory: AppOutputMenu(
                entry: entry,
                devices: devices,
                systemOutputName: systemOutputName,
                onChoose: onChooseOutput
            )
        ) {
            Image(nsImage: entry.icon)
                .resizable()
                .interpolation(.high)
                .saturation(entry.isPlaying ? 1 : 0)
                .opacity(entry.isPlaying ? 1 : 0.6)
                .help(entry.isPlaying ? "Playing" : "Quiet right now")
        }
    }

    private func setPosition(_ position: Double) {
        onVolume(VolumeCurve.volume(atPosition: position))
    }
}
