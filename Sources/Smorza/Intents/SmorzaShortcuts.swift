import AppIntents

/// The actions Shortcuts and Spotlight offer without the user building anything.
struct SmorzaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MuteAllIntent(),
            phrases: ["Mute all apps with \(.applicationName)", "Mute everything in \(.applicationName)"],
            shortTitle: "Mute All Apps",
            systemImageName: "speaker.slash"
        )
        AppShortcut(
            intent: UnmuteAllIntent(),
            phrases: ["Unmute all apps with \(.applicationName)"],
            shortTitle: "Unmute All Apps",
            systemImageName: "speaker.wave.2"
        )
        AppShortcut(
            intent: SetAppVolumeIntent(),
            phrases: ["Set an app's volume with \(.applicationName)", "Change app volume in \(.applicationName)"],
            shortTitle: "Set App Volume",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: MuteAppIntent(),
            phrases: ["Mute an app with \(.applicationName)"],
            shortTitle: "Mute App",
            systemImageName: "speaker.slash.circle"
        )
        AppShortcut(
            intent: SetAppOutputIntent(),
            phrases: ["Change an app's output with \(.applicationName)"],
            shortTitle: "Set App Output",
            systemImageName: "hifispeaker"
        )
    }
}
