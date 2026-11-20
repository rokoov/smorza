import SwiftUI

/// Marks an app that is playing without going through the mixer, which therefore has no level bar.
struct ActivityDot: View {
    private static let size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: Self.size, height: Self.size)
            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}
