import SwiftUI

/// How the panel looks.
struct AppearanceSettings: View {
    @AppStorage(PanelPreferences.tintsSlidersKey) private var tintsSliders = false

    var body: some View {
        Section("Appearance") {
            Toggle("Tint sliders with app colour", isOn: $tintsSliders)
        }
    }
}
