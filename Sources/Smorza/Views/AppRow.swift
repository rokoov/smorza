import MixerCore
import SwiftUI

/// An app's row. A dimmed, grey icon means the app is quiet right now; an orange level means boost.
struct AppRow: View {
    let entry: MixerEntry
    let scale: VolumeScale
    let meters: MeterLevels
    let devices: [OutputDevice]
    let systemOutputName: String
    let onVolume: (Double) -> Void
    let onToggleMute: () -> Void
    let onSolo: () -> Void
    let onChooseOutput: (OutputDevice?) -> Void
    let onTogglePin: () -> Void
    let onIgnore: () -> Void
    /// Tells the panel which row the pointer is over, for scrolling.
    let onHover: (Bool) -> Void
    /// The app's own colour for its slider, level and output icon, or nil for the system accent.
    var tint: Color?
    @State private var isHovered = false

    var body: some View {
        MixerRow(
            title: entry.name,
            level: level,
            position: scale.position(of: entry.volume),
            volume: entry.volume,
            unityMark: scale.allowsBoost ? scale.unityPosition : nil,
            levelStyle: levelStyle,
            titleSymbol: entry.isPinned ? (name: "pin.fill", label: String(localized: "Pinned")) : nil,
            isMuted: entry.isMuted,
            isEnabled: true,
            onChange: setPosition,
            onToggleMute: onToggleMute,
            onSolo: onSolo,
            accessory: AppOutputMenu(
                entry: entry,
                devices: devices,
                systemOutputName: systemOutputName,
                isRevealed: isHovered,
                onChoose: onChooseOutput
            ),
            meter: LevelMeterBar(meters: meters, key: entry.id)
        ) {
            Image(nsImage: entry.icon)
                .resizable()
                .interpolation(.high)
                .saturation(entry.isPlaying ? 1 : 0)
                .opacity(entry.isPlaying ? 1 : 0.6)
                .overlay(alignment: .bottomTrailing) {
                    // A routed app shows its level under the slider; the others get a dot.
                    if entry.isPlaying, !entry.isRouted {
                        ActivityDot()
                    }
                }
                .help(activity)
        }
        .tint(tint)
        .onHover { isInside in
            isHovered = isInside
            onHover(isInside)
        }
        .contextMenu {
            Button(entry.isSolo ? "End Solo" : "Play Solo", action: onSolo)
            Button(entry.isMuted ? "Unmute" : "Mute", action: onToggleMute)
            Button(entry.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Divider()
            Menu("Output") {
                AppOutputChoices(
                    entry: entry,
                    devices: devices,
                    systemOutputName: systemOutputName,
                    onChoose: onChooseOutput
                )
            }
            Divider()
            Button("Ignore \(entry.name)", action: onIgnore)
                .help("Smorza leaves this app's sound alone and stops listing it. Settings lists ignored apps.")
        }
    }

    private var activity: String {
        if !entry.isRunning { return String(localized: "Not running") }
        return entry.isPlaying ? String(localized: "Playing") : String(localized: "Quiet right now")
    }

    private var level: String {
        if entry.isMuted { return String(localized: "Muted") }
        let percent = VolumeCurve.percent(entry.volume)
        return entry.isSolo ? String(localized: "Solo · \(percent)%") : "\(percent)%"
    }

    private var levelStyle: AnyShapeStyle {
        if entry.isSolo, !entry.isMuted { return AnyShapeStyle(.tint) }
        if entry.isBoosted, !entry.isMuted { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }

    private func setPosition(_ position: Double) {
        onVolume(scale.volume(atPosition: position))
    }
}
