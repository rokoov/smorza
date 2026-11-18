import Foundation

/// Remembers each app's setting between launches. Apps at full volume are not stored.
public final class AppVolumeStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private var values: [String: AppVolume]

    public init(defaults: UserDefaults = .standard, storageKey: String = "AppVolumes") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: AppVolume].self, from: data)
        {
            values = decoded
        } else {
            values = [:]
        }
    }

    public subscript(key: String) -> AppVolume {
        get { values[key] ?? AppVolume() }
        set {
            values[key] = newValue.needsRouting ? newValue : nil
            if let data = try? JSONEncoder().encode(values) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    public var adjustedKeys: Set<String> { Set(values.keys) }
}
