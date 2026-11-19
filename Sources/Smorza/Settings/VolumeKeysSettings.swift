import SwiftUI

/// Whether the volume keys change the app in front.
struct VolumeKeysSettings: View {
    let volumeKeys: VolumeKeys

    var body: some View {
        Section("Volume keys") {
            Toggle(
                "Control + volume keys change the app in front",
                isOn: Binding(get: { volumeKeys.isEnabled }, set: { volumeKeys.setEnabled($0) })
            )
            if volumeKeys.isEnabled, !volumeKeys.isTrusted {
                AccessibilityHint()
            }
        }
    }
}
