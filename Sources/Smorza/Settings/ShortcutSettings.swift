import KeyboardShortcuts
import SwiftUI

/// The global shortcuts, each with a recorder to change or clear it.
struct ShortcutSettings: View {
    var body: some View {
        Section("Shortcuts") {
            KeyboardShortcuts.Recorder("Mute all apps", name: .muteAll)
        }
    }
}
