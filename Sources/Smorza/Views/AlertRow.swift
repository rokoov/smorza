import SwiftUI

/// The volume of alert and notification sounds, the system's own, laid out like an app row.
struct AlertRow: View {
    let alerts: AlertVolume

    var body: some View {
        MixerRow(
            title: String(localized: "Notifications & alerts"),
            level: alerts.isMuted ? String(localized: "Muted") : "\(alerts.percent)%",
            position: alerts.volume,
            volume: alerts.volume,
            isMuted: alerts.isMuted,
            isEnabled: true,
            onChange: { alerts.setVolume($0) },
            onToggleMute: { alerts.toggleMute() },
            // Holds the column the app rows use for their output menu, so every slider lines up.
            accessory: Color.clear.frame(width: PanelMetrics.hitTarget, height: PanelMetrics.hitTarget),
            meter: EmptyView()
        ) {
            Image(systemName: alerts.isMuted ? "bell.slash.fill" : "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
                .background(.quaternary, in: Circle())
        }
        .help("The Alert volume from System Settings > Sound, for alerts and notification sounds")
    }
}
