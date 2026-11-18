import Foundation

/// One app's mixer setting. The slider runs 0...1; 1 means the app plays untouched.
public struct AppVolume: Codable, Equatable {
    public var volume: Double
    public var isMuted: Bool

    public init(volume: Double = 1, isMuted: Bool = false) {
        self.volume = volume
        self.isMuted = isMuted
    }

    /// Whether the app's audio has to go through a tap. At full volume and unmuted it plays directly.
    public var needsRouting: Bool {
        isMuted || volume < VolumeCurve.fullVolumeThreshold
    }

    public var gain: Float {
        VolumeCurve.gain(sliderValue: volume, isMuted: isMuted)
    }
}

public enum VolumeCurve {
    /// Slider values this close to the top count as full volume, so a drag to the end lands on 100%.
    public static let fullVolumeThreshold = 0.995

    /// Maps the slider to linear gain. Squaring follows perceived loudness far better than a
    /// straight line: half way is about -12 dB instead of a barely audible -6 dB.
    public static func gain(sliderValue: Double, isMuted: Bool) -> Float {
        if isMuted { return 0 }
        let clamped = min(max(sliderValue, 0), 1)
        if clamped >= fullVolumeThreshold { return 1 }
        return Float(clamped * clamped)
    }

    public static func percent(_ sliderValue: Double) -> Int {
        Int((min(max(sliderValue, 0), 1) * 100).rounded())
    }
}

/// Remembers each app's setting between launches. Apps at full volume are not stored.
public final class AppVolumeStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private var values: [String: AppVolume]

    public init(defaults: UserDefaults = .standard, storageKey: String = "AppVolumes") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: AppVolume].self, from: data) {
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
