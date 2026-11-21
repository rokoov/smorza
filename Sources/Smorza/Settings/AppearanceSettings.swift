import SwiftUI

/// How the panel looks.
struct AppearanceSettings: View {
    @AppStorage(PanelPreferences.tintsSlidersKey) private var tintsSliders = false
    @AppStorage(PanelPreferences.showsAlertsKey) private var showsAlerts = true
    @AppStorage(PanelPreferences.showsVolumeInMenuBarKey) private var showsVolumeInMenuBar = false

    var body: some View {
        Section("Appearance") {
            Toggle("Show Notifications & alerts", isOn: $showsAlerts)
            Toggle("Tint sliders with app colour", isOn: $tintsSliders)
            Toggle("Show the output volume in the menu bar", isOn: $showsVolumeInMenuBar)
        }
    }
}
