import AppKit
import SwiftUI

/// Shown while the volume keys are on but macOS has not allowed the app to catch them yet.
struct AccessibilityHint: View {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    var body: some View {
        HStack(spacing: 6) {
            Text("Needs Accessibility to catch the keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Privacy Settings") {
                if let url = Self.settingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}
