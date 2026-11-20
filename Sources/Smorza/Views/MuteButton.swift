import AppKit
import SwiftUI

/// A speaker that shows the volume and toggles mute; muted turns it orange and crossed out. With
/// `onSolo`, an Option-click plays the app solo instead.
struct MuteButton: View {
    /// The app or device it mutes, for VoiceOver.
    let name: String
    let isMuted: Bool
    let volume: Double
    var onSolo: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: click) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isMuted ? Color.orange : Color.secondary)
                .frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityLabel(isMuted ? "Unmute \(name)" : "Mute \(name)")
    }

    private var helpText: String {
        let mute = isMuted ? "Unmute" : "Mute"
        return onSolo == nil ? mute : "\(mute) · Option-click to play solo"
    }

    private var symbol: String {
        if isMuted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func click() {
        if let onSolo, NSEvent.modifierFlags.contains(.option) {
            onSolo()
        } else {
            action()
        }
    }
}
