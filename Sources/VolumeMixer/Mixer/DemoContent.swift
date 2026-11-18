import AppKit

/// Sample apps and devices for the README screenshots (`--snapshot-demo`). Icons come from the
/// apps on this Mac; a missing app shows the generic icon.
enum DemoContent {
    struct App {
        let name: String
        let path: String
        var volume = 1.0
        var isMuted = false
        var isPlaying = false
    }

    static let apps = [
        App(name: "Google Chrome", path: "/Applications/Google Chrome.app", isPlaying: true),
        App(name: "Spotify", path: "/Applications/Spotify.app", volume: 0.6, isPlaying: true),
        App(name: "Discord", path: "/Applications/Discord.app", volume: 1.4),
        App(name: "Music", path: "/System/Applications/Music.app", volume: 0.8, isMuted: true),
    ]

    static let devices = [
        OutputDevice(id: 9001, name: "MacBook Pro Speakers", symbolName: "laptopcomputer", isBuiltIn: true),
        OutputDevice(id: 9002, name: "AirPods Pro", symbolName: "airpodspro", isBuiltIn: false),
        OutputDevice(id: 9003, name: "Studio Display", symbolName: "display", isBuiltIn: false),
    ]

    static let outputVolume = 0.5

    @MainActor
    static var entries: [MixerEntry] {
        apps.map { app in
            MixerEntry(
                id: app.name,
                name: app.name,
                icon: NSWorkspace.shared.icon(forFile: app.path),
                volume: app.volume,
                isMuted: app.isMuted,
                isPlaying: app.isPlaying
            )
        }
    }
}
