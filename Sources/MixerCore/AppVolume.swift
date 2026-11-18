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
