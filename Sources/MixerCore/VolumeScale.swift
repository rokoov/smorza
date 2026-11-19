/// The range an app's slider covers and how its positions map to volumes. The free scale ends at
/// 100%; the boosted one (a Pro feature) puts 100% three quarters along and spends the last quarter
/// on boost, so 0–100% stays as fine as on the free scale.
public struct VolumeScale: Equatable, Sendable {
    /// Highest volume on this scale.
    public let maximum: Double
    /// Where 100% sits on the slider, 0...1.
    public let unityPosition: Double

    public static let standard = VolumeScale(maximum: 1, unityPosition: 1)
    public static let boosted = VolumeScale(maximum: VolumeCurve.maximum, unityPosition: 0.75)

    /// Slider positions this close to 100% snap onto it while dragging.
    public static let snapDistance = 0.02
    /// One press of a volume key moves the slider this far: sixteen steps like the system volume.
    public static let keyStep = 1.0 / 16
    /// With Shift held, a quarter of that, like the system's fine steps.
    public static let fineKeyStep = 1.0 / 64

    public var allowsBoost: Bool { maximum > 1 }

    /// A saved volume brought onto this scale; a boost saved under Pro plays at 100% without it.
    public func clamped(_ volume: Double) -> Double {
        min(max(volume, 0), maximum)
    }

    /// `snapsToUnity` pulls positions near 100% onto it, which helps a drag; key steps leave it off
    /// or a fine step could never leave 100%.
    public func volume(atPosition position: Double, snapsToUnity: Bool = true) -> Double {
        let clampedPosition = min(max(position, 0), 1)
        if snapsToUnity, abs(clampedPosition - unityPosition) < Self.snapDistance { return 1 }
        if clampedPosition <= unityPosition { return clampedPosition / unityPosition }
        return 1 + (clampedPosition - unityPosition) / (1 - unityPosition) * (maximum - 1)
    }

    public func position(of volume: Double) -> Double {
        let clampedVolume = clamped(volume)
        if clampedVolume <= 1 { return clampedVolume * unityPosition }
        return unityPosition + (clampedVolume - 1) / (maximum - 1) * (1 - unityPosition)
    }

    /// The volume one key press up (`direction` 1) or down (-1) from `volume`. The position is
    /// rounded to the step grid first, so steps from a dragged value line up with the others.
    public func stepped(_ volume: Double, by direction: Int, fine: Bool) -> Double {
        let step = fine ? Self.fineKeyStep : Self.keyStep
        let onGrid = (position(of: volume) / step).rounded() * step
        return self.volume(atPosition: onGrid + Double(direction) * step, snapsToUnity: false)
    }
}
