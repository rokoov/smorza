import SwiftUI

/// What the volume keys change: the Mac's volume, as macOS does, or the playing app.
struct VolumeKeysSettings: View {
    let volumeKeys: VolumeKeys

    var body: some View {
        Section("Volume keys") {
            Picker(
                "Volume keys change",
                selection: Binding(get: { volumeKeys.isEnabled }, set: { volumeKeys.setEnabled($0) })
            ) {
                Text("The Mac's volume").tag(false)
                Text("The playing app").tag(true)
            }
            .pickerStyle(.radioGroup)
            if volumeKeys.isEnabled {
                Text(PlayingAppText.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Hold Option to change the Mac's volume instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !volumeKeys.isTrusted {
                    AccessibilityHint()
                }
            }
        }
    }
}
