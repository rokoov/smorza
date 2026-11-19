import SwiftUI

/// A thin live level under a routed app's slider. Apps playing untouched have no route to measure,
/// so they show none.
struct LevelMeterBar: View {
    let meters: MeterLevels
    let key: String

    private let height: CGFloat = 2
    /// Lines the bar up with the ends of the slider's track.
    private let inset: CGFloat = 2

    var body: some View {
        if let bar = meters.bars[key] {
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint.opacity(0.55))
                    .frame(width: max(0, proxy.size.width * CGFloat(bar)), height: height)
            }
            .frame(height: height)
            .padding(.horizontal, inset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
