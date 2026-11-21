import SwiftUI

/// Open at login, through the system's Login Items, and the welcome window once more.
struct GeneralSettings: View {
    let onShowWelcome: () -> Void
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
            Button("Show Welcome Again", action: onShowWelcome)
        }
        .onAppear { loginItem.refresh() }
    }
}
