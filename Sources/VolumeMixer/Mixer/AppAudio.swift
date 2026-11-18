import CoreAudio
import MixerCore

/// One app as the mixer sees it at a moment: who it is, its audio processes and its setting.
struct AppAudio {
    let identity: AppIdentity
    let clients: [AudioClient]
    let setting: AppVolume

    var key: String { identity.key }
    var isPlaying: Bool { clients.contains(where: \.isPlaying) }
    var processObjectIDs: [AudioObjectID] { clients.map(\.objectID).sorted() }
}
