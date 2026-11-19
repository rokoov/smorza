import CoreAudio
import MixerCore

/// One app as the mixer sees it at a moment: who it is, its audio processes, its settings and the
/// device it plays on.
struct AppAudio {
    let identity: AppIdentity
    let clients: [AudioClient]
    let settings: AppSettings
    /// The volume on the device the app plays on now, brought onto this build's scale.
    let volume: AppVolume
    /// The device the user picked for the app, while it is connected.
    let chosenDevice: OutputDevice?
    /// Where the app plays now: the picked device if connected, otherwise the system output.
    let outputDeviceID: AudioObjectID
    let outputDeviceUID: String
    let outputSymbol: String
    /// Turned down, muted, or playing on another device than the system output.
    let needsRoute: Bool

    var key: String { identity.key }
    var isPlaying: Bool { clients.contains(where: \.isPlaying) }
    var processObjectIDs: [AudioObjectID] { clients.map(\.objectID).sorted() }
}
