/// One app's mixer setting. Volume runs 0...2; 1 means the app plays untouched, above 1 is boost.
public struct AppVolume: Codable, Equatable {
    public var volume: Double
    public var isMuted: Bool

    public init(volume: Double = 1, isMuted: Bool = false) {
        self.volume = volume
        self.isMuted = isMuted
    }

    /// Whether the app's audio has to go through a tap. At 100% and unmuted it plays directly.
    public var needsRouting: Bool {
        isMuted || !VolumeCurve.isUnity(volume)
    }

    public var isBoosted: Bool {
        volume > 1 && !VolumeCurve.isUnity(volume)
    }

    public var gain: Float {
        VolumeCurve.gain(volume: volume, isMuted: isMuted)
    }
}
