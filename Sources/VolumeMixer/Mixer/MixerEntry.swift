import AppKit
import MixerCore

/// One row in the mixer: an app and every process that plays sound for it.
struct MixerEntry: Identifiable, Equatable, MixerRowItem {
    let id: String
    let name: String
    let icon: NSImage
    var volume: Double
    var isMuted: Bool
    var isPlaying: Bool

    var isAdjusted: Bool { AppVolume(volume: volume, isMuted: isMuted).needsRouting }
    var isBoosted: Bool { AppVolume(volume: volume, isMuted: isMuted).isBoosted }
}
