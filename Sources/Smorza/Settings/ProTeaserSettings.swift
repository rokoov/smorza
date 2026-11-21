import AppKit
import SwiftUI

/// What Smorza Pro will add, with a link to the website. Nothing in the free app depends on it.
struct ProTeaserSettings: View {
    private static let url = URL(string: "https://smorza.app/#pro")

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smorza Pro: coming soon, $2.99 once")
                        .font(.headline)
                    Text("Smart call ducking, profiles and a limiter for each app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Learn More") {
                    if let url = Self.url {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
