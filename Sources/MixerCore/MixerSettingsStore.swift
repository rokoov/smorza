import Foundation

/// The mixer's saved settings, kept in user defaults as versioned JSON.
public final class MixerSettingsStore {
    /// Format written by this build. A newer one on disk is left alone, so going back to an older
    /// build never overwrites what a newer one saved.
    public static let currentVersion = 2

    private struct Saved: Codable {
        var version: Int
        var apps: [String: AppSettings]
    }

    private let defaults: UserDefaults
    private let key: String
    private var apps: [String: AppSettings] = [:]
    private var isReadOnly = false

    /// `legacyKey` holds the version 1 format (one volume per app), migrated on first load.
    public init(defaults: UserDefaults = .standard, key: String = "Settings", legacyKey: String = "AppVolumes") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            apps = saved.apps
            isReadOnly = saved.version > Self.currentVersion
        } else if let data = defaults.data(forKey: legacyKey),
            let legacy = try? JSONDecoder().decode([String: AppVolume].self, from: data)
        {
            apps = legacy.mapValues { AppSettings(lastVolume: $0) }
            save()
        }
    }

    public var appKeys: [String] { Array(apps.keys) }

    public func settings(for app: String) -> AppSettings {
        apps[app] ?? AppSettings()
    }

    public func volume(for app: String, on deviceUID: String) -> AppVolume {
        settings(for: app).volume(on: deviceUID)
    }

    public func setVolume(_ volume: AppVolume, for app: String, on deviceUID: String) {
        update(app) { settings in
            settings.volumes[deviceUID] = volume
            settings.lastVolume = volume
        }
    }

    /// Gives the app its own volume on a device it has none for, copied from its last volume, so a
    /// later change on another device leaves this one alone.
    public func adoptVolume(for app: String, on deviceUID: String) {
        guard let settings = apps[app], settings.volumes[deviceUID] == nil else { return }
        update(app) { $0.volumes[deviceUID] = settings.lastVolume ?? AppVolume() }
    }

    public func setOutputDevice(uid: String?, name: String?, for app: String) {
        update(app) { settings in
            settings.outputDeviceUID = uid
            settings.outputDeviceName = uid == nil ? nil : name
        }
    }

    private func update(_ app: String, _ change: (inout AppSettings) -> Void) {
        var settings = settings(for: app)
        change(&settings)
        apps[app] = settings.isDefault ? nil : settings
        save()
    }

    private func save() {
        guard !isReadOnly,
            let data = try? JSONEncoder().encode(Saved(version: Self.currentVersion, apps: apps))
        else { return }
        defaults.set(data, forKey: key)
    }
}
