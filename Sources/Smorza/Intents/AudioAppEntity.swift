import AppIntents

/// An app for the Shortcuts actions: a running app, or one picked earlier that is only installed now.
struct AudioAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let defaultQuery = AudioAppQuery()

    /// The bundle identifier, which is also the key of the app's settings.
    let id: String
    let name: String

    init(_ identity: AppIdentity) {
        id = identity.key
        name = identity.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}
