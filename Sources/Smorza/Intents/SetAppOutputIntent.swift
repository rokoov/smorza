import AppIntents

struct SetAppOutputIntent: AppIntent {
    static let title: LocalizedStringResource = "Set App Output Device"
    static let description = IntentDescription(
        "Sends an app to an output device in Smorza, or back to the system default."
    )

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Parameter(title: "Device")
    var device: OutputDeviceEntity

    @Dependency private var model: MixerModel

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$app) on \(\.$device)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let chosen = device.id == OutputDeviceEntity.systemDefaultID ? nil : model.output.device(withUID: device.id)
        model.setOutputDevice(chosen, for: app.id)
        return .result()
    }
}
