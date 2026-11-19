/// How an app volume becomes gain, and how it reads as a percentage. Volumes run from 0 to
/// `maximum`: 1 is the app untouched, above it is boost. `VolumeScale` maps volumes onto a slider.
public enum VolumeCurve {
    /// Highest volume any scale reaches, 200%. Gain stops here whatever was saved.
    public static let maximum = 2.0
    /// Volumes this close to 100% count as 100%, so the app plays untouched.
    public static let unityTolerance = 0.005

    public static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < unityTolerance
    }

    /// Below 100% the volume is squared, which follows perceived loudness: half way is about
    /// -12 dB instead of a barely audible -6 dB. Above 100% it is linear: 200% doubles the signal.
    public static func gain(volume: Double, isMuted: Bool) -> Float {
        if isMuted { return 0 }
        let clamped = min(max(volume, 0), maximum)
        if isUnity(clamped) { return 1 }
        if clamped < 1 { return Float(clamped * clamped) }
        return Float(clamped)
    }

    public static func percent(_ volume: Double) -> Int {
        Int((min(max(volume, 0), maximum) * 100).rounded())
    }
}
