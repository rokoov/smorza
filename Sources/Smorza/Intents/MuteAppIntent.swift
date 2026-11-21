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
        switch action {
        case .mute: model.setMuted(true, for: app.id)
        case .unmute: model.setMuted(false, for: app.id)
        case .toggle: model.toggleMute(for: app.id)
        }
        return .result()
    }
}
