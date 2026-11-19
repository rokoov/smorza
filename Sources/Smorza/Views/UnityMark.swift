import SwiftUI

/// A short tick where 100% sits on a slider that goes past it, drawn behind the track so the knob
/// covers it when it rests there.
struct UnityMark: View {
    /// Where the tick sits along the slider, 0...1.
    let position: Double
    /// Half a small slider's knob: its centre never comes closer than this to either end.
    private let inset: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.secondary.opacity(0.7))
                .frame(width: 2, height: 9)
                .position(x: inset + (proxy.size.width - 2 * inset) * position, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
