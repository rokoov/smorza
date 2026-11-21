import AppKit
import MixerCore
import SwiftUI

/// The menu bar panel: the output volume, a row per app, the output devices and the footer.
struct MixerPanel: View {
    let model: MixerModel
    let updater: Updater
    let onOpenSettings: () -> Void
    @State private var isSavingProfile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The row under the pointer, which scrolling turns up or down.
    @State private var hoveredRow: String?
    @State private var scrollMonitor = RowScrollMonitor()
    @AppStorage(PanelPreferences.tintsSlidersKey) private var tintsSliders = false
    @AppStorage(PanelPreferences.showsAlertsKey) private var showsAlerts = true
    /// Stand for the output device's row and the alerts row among the app rows' keys.
    private static let outputRowID = "output-device"
    private static let alertsRowID = "alerts"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: PanelMetrics.rowSpacing) {
                OutputRow(output: model.output)
                    .onHover { hover(Self.outputRowID, isInside: $0) }
                if showsAlerts {
                    AlertRow(alerts: model.alerts)
                        .onHover { hover(Self.alertsRowID, isInside: $0) }
                }
            }
            .padding(PanelMetrics.padding)
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
        .onChange(of: model.isPanelVisible, initial: true) { _, isVisible in
            if isVisible {
                scrollMonitor.start(scroll)
            } else {
                scrollMonitor.stop()
                hoveredRow = nil
            }
        }
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
                    onTogglePin: { model.togglePin(for: entry.id) },
                    onIgnore: { model.ignore(entry.id) },
                    onHover: { hover(entry.id, isInside: $0) },
                    tint: tintsSliders ? model.appTints.tint(for: entry.id, icon: entry.icon) : nil
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
        if isVertical, row != Self.outputRowID, row != Self.alertsRowID, model.entries.count > PanelMetrics.visibleRows
        {
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
        } else if row == Self.alertsRowID {
            model.alerts.setVolume(model.alerts.volume + change)
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
            if !model.entries.isEmpty || model.muteAll != nil {
                Button(model.muteAll == nil ? "Mute All" : "Unmute All", action: model.toggleMuteAll)
                    .help(model.muteAll == nil ? "Mutes every app here" : "Gives every app its mute from before")
            }
            if updater.isUpdateWaiting {
                Button("Update Available…") { updater.checkForUpdates() }
                    .buttonStyle(.link)
            }
            Spacer()
            Button {
                onOpenSettings()
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
