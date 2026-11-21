import AppIntents

struct MuteAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute All Apps"
    static let description = IntentDescription("Mutes every app in Smorza. Unmute All Apps gives each its mute back.")

    @Dependency private var model: MixerModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.changeMuteAll(.mute)
        return .result()
    }
}
