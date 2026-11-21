import MixerCore
import SwiftUI

/// What the volume overlay shows: the app, its level as a bar with the 100% mark, and the number.
struct VolumeHUDView: View {
    let name: String
    let icon: NSImage
    let volume: Double
    let isMuted: Bool
    let scale: VolumeScale
    /// Replaces the level text, for news that is not a level.
    var status: String?
    var showsLevel = true

    private let width: CGFloat = 260
    private let cornerRadius: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(status ?? (isMuted ? String(localized: "Muted") : "\(VolumeCurve.percent(volume))%"))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isMuted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                if showsLevel {
                    LevelBar(
                        position: scale.position(of: volume),
                        unityMark: scale.allowsBoost ? scale.unityPosition : nil,
                        isMuted: isMuted
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A read-only level bar, with a tick where 100% sits when the scale goes past it.
private struct LevelBar: View {
    let position: Double
    let unityMark: Double?
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
                if let unityMark {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: 2, height: height + 4)
                        .offset(x: proxy.size.width * unityMark - 1)
                }
            }
        }
        .frame(height: height)
    }
}
