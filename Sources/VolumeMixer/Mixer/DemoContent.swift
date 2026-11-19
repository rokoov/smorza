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
        /// UID of a device from `devices` the app is sent to, or nil for the system output.
        var outputDeviceUID: String?
    }

    static let apps = [
        App(name: "Google Chrome", path: "/Applications/Google Chrome.app", isPlaying: true),
        App(name: "Spotify", path: "/Applications/Spotify.app", volume: 0.6, isPlaying: true),
        App(name: "Discord", path: "/Applications/Discord.app", volume: 0.45, outputDeviceUID: "demo.airpods"),
        App(name: "Music", path: "/System/Applications/Music.app", volume: 0.8, isMuted: true),
    ]

    static let devices = [
        OutputDevice(
            id: 9001,
            uid: "demo.speakers",
            name: "MacBook Pro Speakers",
            symbolName: "laptopcomputer",
            isBuiltIn: true
        ),
        OutputDevice(id: 9002, uid: "demo.airpods", name: "AirPods Pro", symbolName: "airpodspro", isBuiltIn: false),
        OutputDevice(id: 9003, uid: "demo.display", name: "Studio Display", symbolName: "display", isBuiltIn: false),
    ]

    static let outputVolume = 0.5

    /// Live levels of the routed demo apps (Spotify and Discord are turned down, so they have routes).
    static let meterBars: [String: Float] = ["Spotify": 0.72, "Discord": 0.45]

    /// The overlay after Control + volume down in Spotify.
    @MainActor
    static var hud: VolumeHUDView {
        VolumeHUDView(
            name: "Spotify",
            icon: NSWorkspace.shared.icon(forFile: "/Applications/Spotify.app"),
            volume: 0.75,
            isMuted: false,
            scale: ProFeatures.volumeScale
        )
    }

    @MainActor
    static var entries: [MixerEntry] {
        apps.map { app in
            let device = devices.first { $0.uid == app.outputDeviceUID } ?? devices[0]
            return MixerEntry(
                id: app.name,
                name: app.name,
                icon: NSWorkspace.shared.icon(forFile: app.path),
                volume: app.volume,
                isMuted: app.isMuted,
                isPlaying: app.isPlaying,
                outputDeviceUID: app.outputDeviceUID,
                outputDeviceName: app.outputDeviceUID == nil ? nil : device.name,
                outputSymbol: device.symbolName
            )
        }
    }
}
