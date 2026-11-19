import SwiftUI

/// Names the mix as it plays now and saves it as a profile.
struct ProfileEditor: View {
    let onSave: (_ name: String, _ mutesOtherApps: Bool) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var mutesOtherApps = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save the current mix")
                .font(.callout.weight(.semibold))
            TextField("Name, like Gaming or Meeting", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(save)
            Toggle("Mute apps that are not in this mix", isOn: $mutesOtherApps)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .controlSize(.small)
        .padding(PanelMetrics.padding)
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, mutesOtherApps)
    }
}
