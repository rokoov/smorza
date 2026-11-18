import SwiftUI

/// A speaker that shows the volume and toggles mute; muted turns it orange and crossed out.
struct MuteButton: View {
    let isMuted: Bool
    let volume: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isMuted ? Color.orange : Color.secondary)
                .frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isMuted ? "Unmute" : "Mute")
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }

    private var symbol: String {
        if isMuted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
