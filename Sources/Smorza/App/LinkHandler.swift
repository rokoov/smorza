import AppKit
import MixerCore

/// Runs smorza:// links through the same model calls as the Shortcuts actions. A link that names
/// nothing Smorza knows does nothing and says why in the log.
@MainActor
struct LinkHandler {
    /// Words that send an app back to the system output instead of naming a device.
    private static let systemDefaultNames: Set<String> = ["default", "system", "system-default", "system default"]
    /// Enough of a link to recognise it in the log.
    private static let loggedLength = 300

    let model: MixerModel
    let openPanel: () -> Void

    func open(_ url: URL) {
        let link = String(url.absoluteString.prefix(Self.loggedLength))
        switch URLCommand.parse(url) {
        case .failure(let rejection):
            log.error("Ignored \(link, privacy: .public): \(rejection.description, privacy: .public)")
        case .success(let command):
            log.notice("Link: \(link, privacy: .public)")
            run(command)
        }
    }

    private func run(_ command: URLCommand) {
        switch command {
        case .open:
            openPanel()
        case .reset:
            model.resetAll()
        case .muteAll(let change):
            model.changeMuteAll(change)
        case .setVolume(let apps, let percent):
            change(apps) { model.setVolume(percent / 100, for: $0) }
        case .stepVolume(let apps, let direction):
            change(apps) { model.stepVolume(of: $0, by: direction) }
        case .mute(let apps, let change):
            self.change(apps) { model.changeMute(change, for: $0) }
        case .setOutput(let apps, let name):
            guard let device = outputDevice(named: name) else {
                log.error("Ignored a link: no output device is called \(name, privacy: .public)")
                return
            }
            change(apps, showsOverlay: false) { model.setOutputDevice(device, for: $0) }
        }
    }

    /// Changes each app a link names. A single app shows its new volume in the overlay, as a
    /// shortcut does.
    private func change(_ apps: [String], showsOverlay: Bool = true, _ action: (String) -> Void) {
        let keys = apps.compactMap { name in
            let key = model.appKey(matching: name)
            if key == nil {
                log.error("Ignored \(name, privacy: .public) in a link: no such app")
            }
            return key
        }
        keys.forEach(action)
        if showsOverlay, keys.count == 1, let key = keys.first {
            model.showVolumeOverlay(for: key)
        }
    }

    /// A connected device by UID or name, or `.some(nil)` for the system output.
    private func outputDevice(named name: String) -> OutputDevice?? {
        let devices = model.output.devices
        if let device = devices.first(where: { $0.uid == name })
            ?? devices.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        {
            return device
        }
        return Self.systemDefaultNames.contains(name.lowercased()) ? .some(nil) : nil
    }
}
