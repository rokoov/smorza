import SwiftUI

/// How the panel looks.
struct AppearanceSettings: View {
    @AppStorage(PanelPreferences.tintsSlidersKey) private var tintsSliders = false
    @AppStorage(PanelPreferences.showsAlertsKey) private var showsAlerts = true

    var body: some View {
        Section("Appearance") {
            Toggle("Show Notifications & alerts", isOn: $showsAlerts)
            Toggle("Tint sliders with app colour", isOn: $tintsSliders)
        }
    }
}
