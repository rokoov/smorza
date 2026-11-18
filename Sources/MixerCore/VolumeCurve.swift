/// How a slider position becomes an app volume, how a volume becomes gain, and how it reads as a
/// percentage. Volumes run from 0 to 2: 1 is the app untouched, above it is boost.
public enum VolumeCurve {
    /// Highest volume, 200%: boost for quiet calls and videos, kept clean by the renderer's limiter.
    public static let maximum = 2.0
    /// Where 100% sits on the slider. Three quarters keeps 0–100% as fine as without boost and
    /// leaves the last quarter for it.
    public static let unityPosition = 0.75
    /// Volumes this close to 100% count as 100%, so the app plays untouched.
    public static let unityTolerance = 0.005
    /// Slider positions this close to the 100% mark snap onto it while dragging.
    public static let snapDistance = 0.02

    public static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < unityTolerance
    }

    public static func volume(atPosition position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        if abs(clamped - unityPosition) < snapDistance { return 1 }
        if clamped <= unityPosition { return clamped / unityPosition }
        return 1 + (clamped - unityPosition) / (1 - unityPosition) * (maximum - 1)
    }

    public static func position(of volume: Double) -> Double {
        let clamped = min(max(volume, 0), maximum)
        if clamped <= 1 { return clamped * unityPosition }
        return unityPosition + (clamped - 1) / (maximum - 1) * (1 - unityPosition)
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
