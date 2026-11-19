import SwiftUI

/// The last footer line: which version this is, and Sparkle's "Check for Updates…".
struct UpdateRow: View {
    let updater: Updater
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        HStack(spacing: 6) {
            Text("Volume Mixer \(version)")
                .foregroundStyle(.secondary)
            Spacer()
            Button(updater.isUpdateWaiting ? "Update Available…" : "Check for Updates…") {
                updater.checkForUpdates()
            }
            .buttonStyle(.link)
            .fontWeight(updater.isUpdateWaiting ? .semibold : .regular)
            .disabled(!updater.canCheckForUpdates && !updater.isUpdateWaiting)
            .help(updater.isConfigured ? "" : "This build has no update key, so it cannot update itself.")
        }
        .font(.caption)
    }
}
