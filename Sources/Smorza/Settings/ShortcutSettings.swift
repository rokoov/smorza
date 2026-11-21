import KeyboardShortcuts
import SwiftUI

/// The global shortcuts, each with a recorder to change or clear it.
struct ShortcutSettings: View {
    var body: some View {
        Section("Shortcuts") {
            KeyboardShortcuts.Recorder("Open or close the mixer", name: .togglePanel)
            KeyboardShortcuts.Recorder("Mute all apps", name: .muteAll)
            KeyboardShortcuts.Recorder("Turn the playing app up", name: .targetVolumeUp)
            KeyboardShortcuts.Recorder("Turn the playing app down", name: .targetVolumeDown)
            KeyboardShortcuts.Recorder("Mute the playing app", name: .targetMute)
            Text(PlayingAppText.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// What "the playing app" means, for the shortcuts and the volume keys.
enum PlayingAppText {
    static let explanation: LocalizedStringKey =
        "The playing app is the one that started playing last, or the app in front when nothing plays."
}
