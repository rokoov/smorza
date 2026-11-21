/// A change to a mute: on, off, or the opposite of now.
public enum MuteChange: String, Equatable, Sendable {
    case mute
    case unmute
    case toggle

    /// The mute after this change, from `isMuted`.
    public func applied(to isMuted: Bool) -> Bool {
        switch self {
        case .mute: true
        case .unmute: false
        case .toggle: !isMuted
        }
    }
}
