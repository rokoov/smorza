/// How a slider position becomes gain, and how it reads as a percentage.
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
