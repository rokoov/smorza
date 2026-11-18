import CoreAudio

/// A device sound can be sent to, as the output list shows it.
struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbolName: String
    let isBuiltIn: Bool
}
