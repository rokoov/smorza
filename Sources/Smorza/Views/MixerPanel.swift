import AppKit
import MixerCore
import SwiftUI

/// The menu bar panel: the output volume, a row per app, the output devices and the footer.
struct MixerPanel: View {
    let model: MixerModel
    let updater: Updater
    @State private var isSavingProfile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    /// The row under the pointer, which scrolling turns up or down.
    @State private var hoveredRow: String?
    @State private var scrollMonitor = RowScrollMonitor()
    /// Stands for the output device's row among the app rows' keys.
    private static let outputRowID = "output-device"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OutputRow(output: model.output)
                .padding(PanelMetrics.padding)
                .onHover { hover(Self.outputRowID, isInside: $0) }
            Divider()
            if model.captureState == .blocked || (model.captureState == .checking && model.wasCaptureBlocked) {
                CaptureNotice(isRetrying: model.captureState == .checking, onRetry: model.retryCaptureCheck)
            }
            apps
            if model.captureState == .checking, !model.wasCaptureBlocked, model.entries.contains(where: \.isAdjusted) {
                Label(
                    "Waiting for permission to hear other apps. If macOS asks, click Allow.",
                    systemImage: "hourglass"
                )
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
            if model.output.devices.count > 1 {
                Divider()
                OutputPicker(output: model.output)
            }
            if ProFeatures.isProfilesEnabled, isSavingProfile {
                Divider()
                ProfileEditor(
                    onSave: { name, mutesOtherApps in
                        model.saveProfile(named: name, mutesOtherApps: mutesOtherApps)
                        isSavingProfile = false
                    },
                    onCancel: { isSavingProfile = false }
                )
            }
            Divider()
            footer
        }
        .frame(width: PanelMetrics.width)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.entries.map(\.id))
        .background(
            WindowVisibilityReader { isVisible in
                if isVisible {
                    model.panelDidAppear()
                    scrollMonitor.start(scroll)
                } else {
                    scrollMonitor.stop()
                    hoveredRow = nil
                    model.panelDidDisappear()
                }
            }
        )
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
                    scale: model.volumeScale,
                    meters: model.meters,
                    devices: model.output.devices,
                    systemOutputName: model.output.name,
                    onVolume: { model.setVolume($0, for: entry.id) },
                    onToggleMute: { model.toggleMute(for: entry.id) },
                    onSolo: { model.toggleSolo(for: entry.id) },
                    onChooseOutput: { model.setOutputDevice($0, for: entry.id) },
                    onHover: { hover(entry.id, isInside: $0) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(PanelMetrics.padding)
    }

    private func hover(_ row: String, isInside: Bool) {
        if isInside {
            hoveredRow = row
        } else if hoveredRow == row {
            hoveredRow = nil
        }
    }

    /// Scrolling over a row changes its volume. In a list long enough to scroll, scrolling up and
    /// down moves the list, and sideways scrolling still changes the volume.
    private func scroll(_ event: NSEvent) -> Bool {
        guard let row = hoveredRow else { return false }
        let isVertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        if isVertical, row != Self.outputRowID, model.entries.count > PanelMetrics.visibleRows {
            return false
        }
        // Momentum after the fingers lift would keep turning it.
        guard event.momentumPhase.isEmpty else { return true }
        let change = ScrollStep.positionChange(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isInverted: event.isDirectionInvertedFromDevice
        )
        guard change != 0 else { return true }
        if row == Self.outputRowID {
            model.output.setVolume(model.output.volume + change)
        } else {
            model.nudgeVolume(of: row, byPosition: change)
        }
        return true
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
        HStack(spacing: 8) {
            if ProFeatures.isProfilesEnabled {
                ProfilesMenu(
                    profiles: model.profiles,
                    onApply: model.applyProfile,
                    onSave: { isSavingProfile = true },
                    onDelete: model.deleteProfile
                )
            }
            if updater.isUpdateWaiting {
                Button("Update Available…") { updater.checkForUpdates() }
                    .buttonStyle(.link)
            }
            Spacer()
            Button {
                openSettings()
                // A menu bar app is not active, so the window would open behind the others.
                NSApp.activate()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings…")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",")
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, PanelMetrics.padding)
        .padding(.vertical, 8)
    }
}
