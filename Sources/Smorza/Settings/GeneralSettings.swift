import SwiftUI

/// Open at login, through the system's Login Items.
struct GeneralSettings: View {
    @State private var loginItem = LoginItem()

    var body: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
            if loginItem.needsApproval {
                Text("Allow Smorza in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = loginItem.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { loginItem.refresh() }
    }
}
