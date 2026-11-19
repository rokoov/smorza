import CoreAudio

/// A process connected to the audio system.
struct AudioClient: Equatable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    var isPlaying: Bool
}
