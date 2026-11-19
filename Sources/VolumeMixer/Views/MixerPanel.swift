import AppKit
import SwiftUI

/// The menu bar panel: the output volume, a row per app, the output devices and the footer.
struct MixerPanel: View {
    let model: MixerModel
    let updater: Updater
    @State private var loginItem = LoginItem()
    @State private var isSavingProfile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OutputRow(output: model.output)
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
        .background(
            WindowVisibilityReader { isVisible in
                if isVisible {
                    model.panelDidAppear()
                    loginItem.refresh()
                } else {
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
                    onChooseOutput: { model.setOutputDevice($0, for: entry.id) }
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
                if ProFeatures.isProfilesEnabled {
                    ProfilesMenu(
                        profiles: model.profiles,
                        onApply: model.applyProfile,
                        onSave: { isSavingProfile = true },
                        onDelete: model.deleteProfile
                    )
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            Toggle(
                "Control + volume keys change the app in front",
                isOn: Binding(get: { model.volumeKeys.isEnabled }, set: { model.volumeKeys.setEnabled($0) })
            )
            .toggleStyle(.checkbox)
            if model.volumeKeys.isEnabled, !model.volumeKeys.isTrusted {
                HStack(spacing: 6) {
                    Text("Needs Accessibility to catch the keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
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
            UpdateRow(updater: updater)
                .padding(.top, 4)
        }
        .controlSize(.small)
        .padding(.horizontal, PanelMetrics.padding)
        .padding(.vertical, 10)
    }
}
