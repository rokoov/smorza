import MixerCore

/// Features held back for the Pro version. The free build ships with them off; their code stays, so
/// Pro can turn them on behind a license check without restructuring anything.
enum ProFeatures {
    /// Volumes above 100%, kept clean by the renderer's limiter.
    static let isBoostEnabled = false
    /// Saved mixes and their Control-Option-1 to 9 shortcuts.
    static let isProfilesEnabled = false

    /// The slider scale this build offers.
    static var volumeScale: VolumeScale {
        isBoostEnabled ? .boosted : .standard
    }
}
