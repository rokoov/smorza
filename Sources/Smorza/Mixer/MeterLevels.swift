import MixerCore
import Observation

/// The live bar lengths of routed apps while the panel is open, by app key. Kept apart from the
/// rows, so twenty updates a second redraw the bars and nothing else.
@MainActor
@Observable
final class MeterLevels {
    private(set) var bars: [String: Float] = [:]

    /// Takes new peaks: bars rise at once and, with `isSmoothed`, fall back gently; without it
    /// (Reduce Motion) they jump straight to each reading.
    func update(with peaks: [String: Float], isSmoothed: Bool) {
        var next: [String: Float] = [:]
        for (key, peak) in peaks {
            let target = LevelMeter.fraction(ofPeak: peak)
            next[key] = isSmoothed ? LevelMeter.next(from: bars[key] ?? 0, toward: target) : target
        }
        if next != bars {
            bars = next
        }
    }

    func clear() {
        if !bars.isEmpty {
            bars = [:]
        }
    }

    /// Fixed bars for README screenshots.
    func showDemo(_ demoBars: [String: Float]) {
        bars = demoBars
    }
}
