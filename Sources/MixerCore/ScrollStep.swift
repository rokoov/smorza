/// How far scrolling over a row moves its slider. Up or right, as the fingers or the wheel move,
/// turns it up, whichever way the Mac's scroll direction is set.
public enum ScrollStep {
    /// Of the slider's length per point a trackpad reports: 200 points cross the whole slider.
    public static let perPoint = 0.005
    /// Per line a mouse wheel reports: one notch is 5%.
    public static let perLine = 0.05
    /// The most one event moves, so an accelerated wheel cannot fling the slider to an end.
    public static let maximum = 0.1

    /// The change in slider position for one scroll event. The deltas say how content would move,
    /// and with natural scrolling content moves with the fingers, so `isInverted` turns them round.
    public static func positionChange(deltaX: Double, deltaY: Double, isPrecise: Bool, isInverted: Bool) -> Double {
        let up = isInverted ? -deltaY : deltaY
        let right = isInverted ? deltaX : -deltaX
        let movement = abs(up) >= abs(right) ? up : right
        let change = movement * (isPrecise ? perPoint : perLine)
        return min(max(change, -maximum), maximum)
    }

    /// The arrow keys on a focused slider: 5%, or 1% with Shift.
    public static func keyChange(isUp: Bool, isFine: Bool) -> Double {
        (isFine ? 0.01 : 0.05) * (isUp ? 1 : -1)
    }
}
