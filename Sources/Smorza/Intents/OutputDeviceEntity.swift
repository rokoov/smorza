import AppIntents

/// An output device for the Shortcuts actions, or the system default, which follows macOS's choice.
struct OutputDeviceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Output Device"
    static let defaultQuery = OutputDeviceQuery()
    /// Stands for the system default among the device UIDs.
    static let systemDefaultID = "system-default"

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}
