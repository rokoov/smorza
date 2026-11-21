import AppIntents

/// Offers the running apps, and still finds an app a saved shortcut names while it is not running.
struct AudioAppQuery: EntityQuery {
    @Dependency private var model: MixerModel

    @MainActor
    func entities(for identifiers: [AudioAppEntity.ID]) async throws -> [AudioAppEntity] {
        identifiers.compactMap(model.shortcutApp(id:)).map(AudioAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AudioAppEntity] {
        model.shortcutApps().map(AudioAppEntity.init)
    }
}
