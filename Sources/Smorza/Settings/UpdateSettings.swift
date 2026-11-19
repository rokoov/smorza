import SwiftUI

/// Sparkle's automatic checks and "Check for Updates…", under the version. Right-clicking the
/// version copies a report for a bug report.
struct UpdateSettings: View {
    let updater: Updater
    let onCopyDiagnostics: @MainActor () async -> Void
    @State private var copyState = CopyState.idle
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        Section("Updates") {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.setAutomaticallyChecks($0) })
            )
            .disabled(!updater.isConfigured)
            HStack {
                Text(versionLabel)
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button("Copy Diagnostics") {
                            Task { await copyDiagnostics() }
                        }
                    }
                Spacer()
                Button(updater.isUpdateWaiting ? "Update Available…" : "Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates && !updater.isUpdateWaiting)
                .help(updater.isConfigured ? "" : "This build has no update key, so it cannot update itself.")
            }
        }
    }

    private enum CopyState {
        case idle, copying, copied
    }

    private var versionLabel: String {
        switch copyState {
        case .idle: "Smorza \(version)"
        case .copying: "Copying diagnostics…"
        case .copied: "Diagnostics copied"
        }
    }

    private func copyDiagnostics() async {
        guard copyState == .idle else { return }
        copyState = .copying
        await onCopyDiagnostics()
        copyState = .copied
        try? await Task.sleep(for: .seconds(2))
        copyState = .idle
    }
}
