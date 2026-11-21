import SwiftUI

/// The apps Smorza leaves alone, each with a way back.
struct IgnoredAppsSettings: View {
    let model: MixerModel

    var body: some View {
        Section("Ignored apps") {
            if model.ignoredApps.isEmpty {
                Text(
                    "Right-click an app in the mixer and choose Ignore to leave its sound alone and keep it off the list."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.ignoredApps, id: \.self) { key in
                    let app = model.ignoredIdentity(key)
                    HStack(spacing: 8) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(app.name)
                        Spacer()
                        Button("Stop Ignoring") { model.stopIgnoring(key) }
                            .accessibilityLabel("Stop ignoring \(app.name)")
                    }
                }
            }
        }
    }
}
