import SwiftUI

/// The last footer line: which version this is and Sparkle's "Check for Updates…". Right-clicking
/// the version copies a report for a bug report.
struct VersionRow: View {
    let updater: Updater
    let onCopyDiagnostics: @MainActor () async -> Void
    @State private var copyState = CopyState.idle
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
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
            .buttonStyle(.link)
            .fontWeight(updater.isUpdateWaiting ? .semibold : .regular)
            .disabled(!updater.canCheckForUpdates && !updater.isUpdateWaiting)
            .help(updater.isConfigured ? "" : "This build has no update key, so it cannot update itself.")
        }
        .font(.caption)
    }

    private enum CopyState {
        case idle, copying, copied
    }

    private var label: String {
        switch copyState {
        case .idle: "Volume Mixer \(version)"
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
