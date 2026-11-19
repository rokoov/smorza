import SwiftUI

struct VolumeMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MixerPanel(model: appDelegate.model, updater: appDelegate.updater)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel("Volume Mixer")
        }
        .menuBarExtraStyle(.window)
    }
}
