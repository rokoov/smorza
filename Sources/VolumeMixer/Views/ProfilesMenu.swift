import MixerCore
import SwiftUI

/// Switches between saved mixes, saves the one playing now and deletes old ones. The first nine
/// show their Control-Option shortcut, which also works with the panel closed.
struct ProfilesMenu: View {
    let profiles: [Profile]
    let onApply: (Profile) -> Void
    let onSave: () -> Void
    let onDelete: (Profile) -> Void

    var body: some View {
        Menu("Profiles") {
            if profiles.isEmpty {
                Text("No profiles yet")
            }
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                profileButton(profile, number: index + 1)
            }
            Divider()
            Button("Save Current Mix…", action: onSave)
            if !profiles.isEmpty {
                Menu("Delete") {
                    ForEach(profiles) { profile in
                        Button(profile.name) { onDelete(profile) }
                    }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func profileButton(_ profile: Profile, number: Int) -> some View {
        let button = Button(profile.name) { onApply(profile) }
        if number <= 9, let digit = String(number).first {
            button.keyboardShortcut(KeyEquivalent(digit), modifiers: [.control, .option])
        } else {
            button
        }
    }
}
