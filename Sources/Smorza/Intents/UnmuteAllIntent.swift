import AppIntents

struct UnmuteAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Unmute All Apps"
    static let description = IntentDescription("Gives every app the mute it had before Mute All Apps.")

    @Dependency private var model: MixerModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.changeMuteAll(.unmute)
        return .result()
    }
}
