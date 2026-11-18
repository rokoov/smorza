import AppKit
import MixerCore
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 320
    static let padding: CGFloat = 16
    static let iconSize: CGFloat = 28
    static let rowSpacing: CGFloat = 14
    static let rowHeight: CGFloat = 44
    /// Rows shown before the app list starts to scroll.
    static let visibleRows = 6
    static let percentWidth: CGFloat = 34
    static let hitTarget: CGFloat = 28
}

struct MixerPanel: View {
    let model: MixerModel
    @State private var loginItem = LoginItem()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OutputRow(output: model.output)
                .padding(PanelMetrics.padding)
            Divider()
            if model.permission == .denied {
                PermissionNotice()
            }
            apps
            if model.permission == .undetermined, model.entries.contains(where: { $0.volume < 1 || $0.isMuted }) {
                Text("If macOS asks to record system audio, allow it. That is how one app gets quieter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PanelMetrics.padding)
                    .padding(.bottom, 12)
            }
            if let routingError = model.routingError {
                Label(routingError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, PanelMetrics.padding)
                    .padding(.bottom, 12)
            }
            Divider()
            footer
        }
        .frame(width: PanelMetrics.width)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.entries.map(\.id))
        .onAppear {
            model.panelDidAppear()
            loginItem.refresh()
        }
        .onDisappear { model.panelDidDisappear() }
    }

    @ViewBuilder
    private var apps: some View {
        if model.entries.isEmpty {
            VStack(spacing: 4) {
                Text("Nothing is playing")
                    .font(.callout)
                Text("Apps show up here while they play sound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if model.entries.count <= PanelMetrics.visibleRows {
            rows
        } else {
            ScrollView {
                rows
            }
            .frame(height: CGFloat(PanelMetrics.visibleRows) * (PanelMetrics.rowHeight + PanelMetrics.rowSpacing))
            .mask(fadedEdges)
        }
    }

    private var rows: some View {
        VStack(spacing: PanelMetrics.rowSpacing) {
            ForEach(model.entries) { entry in
                AppRow(
                    entry: entry,
                    onVolume: { model.setVolume($0, for: entry.id) },
                    onToggleMute: { model.toggleMute(for: entry.id) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(PanelMetrics.padding)
    }

    /// Rows fade out under the scroll edges instead of being cut off.
    private var fadedEdges: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 12)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            if loginItem.needsApproval {
                Text("Allow Volume Mixer in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = loginItem.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, PanelMetrics.padding)
        .padding(.vertical, 10)
    }
}

/// Icon, name and level on top, the slider below, mute on the right. The output device uses the
/// same layout so every slider, level and mute button lines up in one column.
struct MixerRow<Icon: View>: View {
    let title: String
    let level: String
    let value: Double
    let isMuted: Bool
    let isEnabled: Bool
    let onChange: (Double) -> Void
    let onToggleMute: () -> Void
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
                    Spacer(minLength: 8)
                    Text(level)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                    .controlSize(.small)
                    .disabled(!isEnabled)
                    .opacity(isMuted ? 0.45 : 1)
            }
            MuteButton(isMuted: isMuted, volume: value, action: onToggleMute)
        }
        .frame(minHeight: PanelMetrics.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct AppRow: View {
    let entry: MixerEntry
    let onVolume: (Double) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        MixerRow(
            title: entry.name,
            level: entry.isMuted ? "Muted" : "\(VolumeCurve.percent(entry.volume))%",
            value: entry.volume,
            isMuted: entry.isMuted,
            isEnabled: true,
            onChange: onVolume,
            onToggleMute: onToggleMute
        ) {
            Image(nsImage: entry.icon)
                .resizable()
                .interpolation(.high)
                .saturation(entry.isPlaying ? 1 : 0)
                .opacity(entry.isPlaying ? 1 : 0.6)
                .help(entry.isPlaying ? "Playing" : "Quiet right now")
        }
    }
}

struct OutputRow: View {
    let output: SystemOutput

    var body: some View {
        MixerRow(
            title: output.name,
            level: output.canSetVolume ? (output.isMuted ? "Muted" : "\(VolumeCurve.percent(output.volume))%") : "Fixed",
            value: output.volume,
            isMuted: output.isMuted,
            isEnabled: output.canSetVolume,
            onChange: { output.setVolume($0) },
            onToggleMute: { output.setMuted(!output.isMuted) }
        ) {
            // A quiet plate: the apps below are what the panel is for.
            Image(systemName: output.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .accessibilityLabel("Output volume, \(output.name)")
    }
}

struct MuteButton: View {
    let isMuted: Bool
    let volume: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isMuted ? Color.orange : Color.secondary)
                .frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isMuted ? "Unmute" : "Mute")
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }

    private var symbol: String {
        if isMuted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct PermissionNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Audio access is off", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Turn on Volume Mixer under Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Until then every app plays at full volume.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PanelMetrics.padding)
    }
}
