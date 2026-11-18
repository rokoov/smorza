import MixerCore
import SwiftUI

/// An app's row. A dimmed, grey icon means the app is quiet right now; an orange level means boost.
struct AppRow: View {
    let entry: MixerEntry
    let devices: [OutputDevice]
    let systemOutputName: String
    let onVolume: (Double) -> Void
    let onToggleMute: () -> Void
    let onSolo: () -> Void
    let onChooseOutput: (OutputDevice?) -> Void

    var body: some View {
        MixerRow(
            title: entry.name,
            level: level,
            position: VolumeCurve.position(of: entry.volume),
            volume: entry.volume,
            unityMark: VolumeCurve.unityPosition,
            levelStyle: levelStyle,
            isMuted: entry.isMuted,
            isEnabled: true,
            onChange: setPosition,
            onToggleMute: onToggleMute,
            onSolo: onSolo,
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
        .contextMenu {
            Button(entry.isSolo ? "End Solo" : "Play Solo", action: onSolo)
            Button(entry.isMuted ? "Unmute" : "Mute", action: onToggleMute)
        }
    }

    private var level: String {
        if entry.isMuted { return "Muted" }
        let percent = "\(VolumeCurve.percent(entry.volume))%"
        return entry.isSolo ? "Solo · \(percent)" : percent
    }

    private var levelStyle: AnyShapeStyle {
        if entry.isSolo, !entry.isMuted { return AnyShapeStyle(.tint) }
        if entry.isBoosted, !entry.isMuted { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }

    private func setPosition(_ position: Double) {
        onVolume(VolumeCurve.volume(atPosition: position))
    }
}
