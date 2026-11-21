import KeyboardShortcuts
import SwiftUI

/// The global shortcuts, each with a recorder to change or clear it.
struct ShortcutSettings: View {
    var body: some View {
        Section("Shortcuts") {
            ShortcutRow("Open or close the mixer", name: .togglePanel)
            ShortcutRow("Mute all apps", name: .muteAll)
            ShortcutRow("Turn the playing app up", name: .targetVolumeUp)
            ShortcutRow("Turn the playing app down", name: .targetVolumeDown)
            ShortcutRow("Mute the playing app", name: .targetMute)
            Text(PlayingAppText.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A shortcut's name and its recorder.
private struct ShortcutRow: View {
    let title: LocalizedStringKey
    let name: KeyboardShortcuts.Name

    init(_ title: LocalizedStringKey, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
    }

    var body: some View {
        LabeledContent {
            WideRecorder(name: name)
        } label: {
            Text(title)
        }
    }
}

/// The package's recorder, wider than the 130 points it keeps to: its placeholder is "Kurzbefehl
/// aufnehmen" in German and "Enregistrer le raccourci" in French.
private struct WideRecorder: NSViewRepresentable {
    private static let width: CGFloat = 190

    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        KeyboardShortcuts.RecorderCocoa(for: name)
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        recorder.shortcutName = name
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: KeyboardShortcuts.RecorderCocoa,
        context: Context
    ) -> CGSize? {
        CGSize(width: Self.width, height: nsView.intrinsicContentSize.height)
    }
}

/// What "the playing app" means, for the shortcuts and the volume keys.
enum PlayingAppText {
    static let explanation: LocalizedStringKey =
        "The playing app is the one that started playing last, or the app in front when nothing plays."
}
