import KeyboardShortcuts

/// The global shortcuts, which the user can change in Settings. KeyboardShortcuts keeps them in
/// the app's defaults and registers them as Carbon hot keys, which need no permission.
extension KeyboardShortcuts.Name {
    static let muteAll = Self("muteAll", default: .init(.m, modifiers: [.control, .option]))
}
