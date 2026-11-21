import AppIntents

struct MuteAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute App"
    static let description = IntentDescription("Mutes or unmutes an app in Smorza, or toggles its mute.")

    @Parameter(title: "Action", default: .toggle)
    var action: MuteAction

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Dependency private var model: MixerModel

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) \(\.$app)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        model.changeMute(action.change, for: app.id)
        return .result()
    }
}
