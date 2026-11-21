import KeyboardShortcuts

/// The global shortcuts, which the user can change in Settings. KeyboardShortcuts keeps them in
/// the app's defaults and registers them as Carbon hot keys, which need no permission. Only Mute
/// All has one from the start.
extension KeyboardShortcuts.Name {
    static let muteAll = Self("muteAll", default: .init(.m, modifiers: [.control, .option]))
    static let togglePanel = Self("togglePanel")
    static let targetVolumeUp = Self("targetVolumeUp")
    static let targetVolumeDown = Self("targetVolumeDown")
    static let targetMute = Self("targetMute")
}
