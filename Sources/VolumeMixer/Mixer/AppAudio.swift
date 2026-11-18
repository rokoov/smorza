import CoreAudio
import MixerCore

/// One app as the mixer sees it at a moment: who it is, its audio processes, its settings and the
/// device it plays on.
struct AppAudio {
    let identity: AppIdentity
    let clients: [AudioClient]
    let settings: AppSettings
    /// The device the user picked for the app, while it is connected.
    let chosenDevice: OutputDevice?
    /// Where the app plays now: the picked device if connected, otherwise the system output.
    let outputDeviceID: AudioObjectID
    let outputDeviceUID: String
    let outputSymbol: String
    /// Plays on a picked device other than the system output, so it needs a route even at 100%.
    let isRedirected: Bool

    var key: String { identity.key }
    var isPlaying: Bool { clients.contains(where: \.isPlaying) }
    var processObjectIDs: [AudioObjectID] { clients.map(\.objectID).sorted() }
    var volume: AppVolume { settings.volume(on: outputDeviceUID) }
    var needsRoute: Bool { volume.needsRouting || isRedirected }
}
