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
    /// The device the user picked for the app, or nil when it follows the system output.
    var outputDeviceUID: String?
    var outputDeviceName: String?
    /// The symbol of the device the app plays on now.
    var outputSymbol: String
    /// False while the picked device is away and the app falls back to the system output.
    var isOutputConnected = true
    /// Playing solo: every other app in the mixer is muted.
    var isSolo = false

    var isAdjusted: Bool { AppVolume(volume: volume, isMuted: isMuted).needsRouting }
    var isBoosted: Bool { AppVolume(volume: volume, isMuted: isMuted).isBoosted }
}
