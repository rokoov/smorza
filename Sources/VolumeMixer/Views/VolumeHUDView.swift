import MixerCore
import SwiftUI

/// What the volume overlay shows: the app, its level as a bar with the 100% mark, and the number.
struct VolumeHUDView: View {
    let name: String
    let icon: NSImage
    let volume: Double
    let isMuted: Bool

    private let width: CGFloat = 260
    private let cornerRadius: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(isMuted ? "Muted" : "\(VolumeCurve.percent(volume))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isMuted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                LevelBar(position: VolumeCurve.position(of: volume), isMuted: isMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A read-only level bar with a tick where 100% sits.
private struct LevelBar: View {
    let position: Double
    let isMuted: Bool

    private let height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .frame(width: proxy.size.width * position)
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: 2, height: height + 4)
                    .offset(x: proxy.size.width * VolumeCurve.unityPosition - 1)
            }
        }
        .frame(height: height)
    }
}
