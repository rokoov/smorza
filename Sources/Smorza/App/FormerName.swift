import Foundation
import MixerCore

/// Smorza was called Volume Mixer until 0.2.1 and kept its settings under that bundle identifier.
/// The first launch under the new name copies them over, so the mix carries across the rename.
enum FormerName {
    static let bundleIdentifier = "com.rokoov.volumemixer"
    private static let keys = [
        MixerSettingsStore.standardKey,
        MixerSettingsStore.standardLegacyKey,
        VolumeKeys.enabledKey,
    ]

    static func adoptSettings(into defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: MixerSettingsStore.standardKey) == nil,
            let former = UserDefaults(suiteName: bundleIdentifier),
            keys.contains(where: { former.object(forKey: $0) != nil })
        else { return }
        for key in keys {
            if let value = former.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        log.notice("Copied the settings of Volume Mixer")
    }
}
