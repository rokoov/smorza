import MixerCore
import SwiftUI

/// Icon, name and level on top, the slider below, mute on the right. The output device uses the
/// same layout so every slider, level and mute button lines up in one column.
struct MixerRow<Icon: View, Accessory: View, Meter: View>: View {
    let title: String
    let level: String
    /// Slider position, 0...1.
    let position: Double
    /// The volume the position stands for, which picks the speaker symbol.
    let volume: Double
    /// Where 100% sits on a slider that goes past it; nil draws no mark.
    var unityMark: Double?
    /// Colour of the level text: orange for boost, the accent for solo.
    var levelStyle = AnyShapeStyle(.secondary)
    /// A small symbol after the title, such as the pin of a pinned app, with what it says.
    var titleSymbol: (name: String, label: String)?
    let isMuted: Bool
    let isEnabled: Bool
    let onChange: (Double) -> Void
    let onToggleMute: () -> Void
    var onSolo: (() -> Void)?
    /// Sits before the mute button: an app's output menu, nothing for the device row.
    let accessory: Accessory
    /// Drawn along the bottom of the slider: a routed app's live level, nothing otherwise.
    let meter: Meter
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let titleSymbol {
                        Image(systemName: titleSymbol.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(titleSymbol.label)
                    }
                    Spacer(minLength: 8)
                    Text(level)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(levelStyle)
                }
                Slider(value: Binding(get: { position }, set: onChange), in: 0...1)
                    .controlSize(.small)
                    .background {
                        if let unityMark {
                            UnityMark(position: unityMark)
                        }
                    }
                    .overlay(alignment: .bottom) { meter }
                    .disabled(!isEnabled)
                    .opacity(isMuted ? 0.45 : 1)
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) {
                        press in
                        let isUp = press.key == .rightArrow || press.key == .upArrow
                        move(by: ScrollStep.keyChange(isUp: isUp, isFine: press.modifiers.contains(.shift)))
                        return .handled
                    }
                    .accessibilityLabel("\(title) volume")
                    .accessibilityValue(level)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: move(by: ScrollStep.keyChange(isUp: true, isFine: false))
                        case .decrement: move(by: ScrollStep.keyChange(isUp: false, isFine: false))
                        @unknown default: break
                        }
                    }
                    .help(unityMark == nil ? "" : "Past the mark boosts above 100%")
            }
            accessory
            MuteButton(name: title, isMuted: isMuted, volume: volume, onSolo: onSolo, action: onToggleMute)
        }
        .frame(minHeight: PanelMetrics.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func move(by change: Double) {
        guard isEnabled else { return }
        onChange(min(max(position + change, 0), 1))
    }
}
