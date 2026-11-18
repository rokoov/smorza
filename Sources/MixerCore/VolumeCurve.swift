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
    /// One press of a volume key moves the slider this far: sixteen steps like the system volume,
    /// with 100% landing on the twelfth.
    public static let keyStep = 1.0 / 16
    /// With Shift held, a quarter of that, like the system's fine steps.
    public static let fineKeyStep = 1.0 / 64

    public static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < unityTolerance
    }

    /// `snapsToUnity` pulls positions near the 100% mark onto it, which helps a drag; key steps
    /// leave it off or a fine step could never leave 100%.
    public static func volume(atPosition position: Double, snapsToUnity: Bool = true) -> Double {
        let clamped = min(max(position, 0), 1)
        if snapsToUnity, abs(clamped - unityPosition) < snapDistance { return 1 }
        if clamped <= unityPosition { return clamped / unityPosition }
        return 1 + (clamped - unityPosition) / (1 - unityPosition) * (maximum - 1)
    }

    public static func position(of volume: Double) -> Double {
        let clamped = min(max(volume, 0), maximum)
        if clamped <= 1 { return clamped * unityPosition }
        return unityPosition + (clamped - 1) / (maximum - 1) * (1 - unityPosition)
    }

    /// The volume one key press up (`direction` 1) or down (-1) from `volume`. The position is
    /// rounded to the step grid first, so steps from a dragged value line up with the others.
    public static func stepped(_ volume: Double, by direction: Int, fine: Bool) -> Double {
        let step = fine ? fineKeyStep : keyStep
        let onGrid = (position(of: volume) / step).rounded() * step
        return self.volume(atPosition: onGrid + Double(direction) * step, snapsToUnity: false)
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
