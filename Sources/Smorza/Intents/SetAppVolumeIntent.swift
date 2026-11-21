import AppIntents

struct SetAppVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set App Volume"
    static let description = IntentDescription("Sets an app's volume in Smorza, from 0 to 100%.")

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Parameter(title: "Volume", inclusiveRange: (0, 100))
    var volume: Int

    @Dependency private var model: MixerModel

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$app) volume to \(\.$volume)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        model.setVolume(Double(volume) / 100, for: app.id)
        return .result()
    }
}
