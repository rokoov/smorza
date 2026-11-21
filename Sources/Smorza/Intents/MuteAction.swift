import AppIntents
import MixerCore

/// What Mute App does: mute, unmute, or the opposite of now.
enum MuteAction: String, AppEnum {
    case mute
    case unmute
    case toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mute Action"
    static let caseDisplayRepresentations: [MuteAction: DisplayRepresentation] = [
        .mute: "Mute",
        .unmute: "Unmute",
        .toggle: "Toggle mute for",
    ]

    var change: MuteChange {
        switch self {
        case .mute: .mute
        case .unmute: .unmute
        case .toggle: .toggle
        }
    }
}
