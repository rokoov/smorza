import Foundation

/// How a route's peak becomes the length of a level bar: on a decibel scale, rising at once and
/// falling back gently so the bar reads as a level rather than a flicker.
public enum LevelMeter {
    /// The quietest level the bar shows, in dB below full scale; anything quieter is empty.
    public static let floorDecibels: Float = -60
    /// The most a bar falls in one update, as a share of its length. At 20 updates a second a full
    /// bar empties in under a second.
    public static let fallPerUpdate: Float = 0.06

    /// The bar length, 0...1, for a peak sample value (1 is full scale).
    public static func fraction(ofPeak peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(peak)
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }

    /// The next bar length: up to `target` at once, down towards it by at most `fallPerUpdate`.
    public static func next(from previous: Float, toward target: Float) -> Float {
        max(target, previous - fallPerUpdate)
    }
}
