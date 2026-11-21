import AppKit
import SwiftUI

/// The first-launch window: what the System Audio Recording permission is for, then the macOS
/// dialog, help if it was refused, and where to find the mixer.
struct WelcomeView: View {
    private static let width: CGFloat = 440
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    let model: MixerModel
    let onFinish: () -> Void
    /// Fixes the step, for the snapshots; nil follows the capture check.
    var shownStep: WelcomeStep?
    @State private var hasContinued = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            content
        }
        .padding(28)
        .frame(width: Self.width)
    }

    private var step: WelcomeStep {
        if let shownStep { return shownStep }
        return hasContinued ? WelcomeStep(captureState: model.captureState) : .intro
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            heading("Welcome to Smorza", "Every app gets its own volume, mute and output.")
            message(
                "To change an app's volume, Smorza plays the app's sound through itself, which macOS calls System Audio Recording. Smorza uses it only for that: nothing is ever recorded, saved or sent anywhere."
            )
            Button("Continue") {
                hasContinued = true
                model.requestCapturePermission()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        case .waiting:
            heading("Waiting for macOS", "In the dialog macOS shows, click Allow.")
            ProgressView()
                .controlSize(.small)
            Button("No dialog? Open System Settings", action: openSettings)
                .buttonStyle(.link)
        case .denied:
            heading("Smorza can't change app volumes yet", nil)
            message(
                "In System Settings, open Privacy & Security, then Screen & System Audio Recording, and turn on Smorza under System Audio Recording Only. Then try again."
            )
            HStack(spacing: 12) {
                Button("Open System Settings", action: openSettings)
                    .keyboardShortcut(.defaultAction)
                Button("Try Again") {
                    model.requestCapturePermission()
                }
            }
            .controlSize(.large)
        case .done:
            heading("You're all set", nil)
            HStack(spacing: 6) {
                Text("Smorza lives in your menu bar. Click")
                Image(systemName: "slider.horizontal.3")
                    .accessibilityLabel("the Smorza icon")
                Text("to open the mixer.")
            }
            .foregroundStyle(.secondary)
            Button("Done", action: onFinish)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private func heading(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSettings() {
        if let url = Self.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
