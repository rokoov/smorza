import AppIntents

/// The system default, then every output device connected now.
struct OutputDeviceQuery: EntityQuery {
    @Dependency private var model: MixerModel

    @MainActor
    func entities(for identifiers: [OutputDeviceEntity.ID]) async throws -> [OutputDeviceEntity] {
        let devices = allDevices()
        return identifiers.compactMap { id in devices.first { $0.id == id } }
    }

    @MainActor
    func suggestedEntities() async throws -> [OutputDeviceEntity] {
        allDevices()
    }

    @MainActor
    private func allDevices() -> [OutputDeviceEntity] {
        let systemDefault = OutputDeviceEntity(id: OutputDeviceEntity.systemDefaultID, name: "System Default")
        return [systemDefault] + model.output.devices.map { OutputDeviceEntity(id: $0.uid, name: $0.name) }
    }
}
