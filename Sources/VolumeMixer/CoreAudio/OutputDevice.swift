import CoreAudio

/// A device sound can be sent to, as the output lists show it.
struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    /// Stays the same across launches and reconnects, unlike `id`; settings remember devices by it.
    let uid: String
    let name: String
    let symbolName: String
    let isBuiltIn: Bool
}
