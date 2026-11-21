import SwiftUI

/// The settings window: the few switches that would only crowd the panel.
struct SettingsView: View {
    private static let width: CGFloat = 460

    let model: MixerModel
    let updater: Updater
    let onShowWelcome: () -> Void

    var body: some View {
        Form {
            GeneralSettings(onShowWelcome: onShowWelcome)
            ShortcutSettings()
            VolumeKeysSettings(volumeKeys: model.volumeKeys)
            OutputSettings(model: model)
            UpdateSettings(updater: updater, onCopyDiagnostics: model.copyDiagnostics)
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
