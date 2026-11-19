import AppKit
import SwiftUI

/// Shown when the capture check failed: no app is muted, so every app keeps playing at full volume.
struct CaptureNotice: View {
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Smorza can't hear other apps", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(
                "Turn on Smorza under Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, then try again. Until then every app plays at full volume."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open System Settings") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button(isRetrying ? "Checking…" : "Try Again", action: onRetry)
                    .disabled(isRetrying)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PanelMetrics.padding)
    }
}
