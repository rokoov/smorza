import SwiftUI

/// Liquid Glass behind the panel on macOS 26 and later; earlier versions keep the system's panel
/// material as it was. The glass sits behind the rows rather than holding them, so text, sliders
/// and app colours keep their own look instead of turning monochrome on the glass.
struct PanelGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect)
            }
        } else {
            content
        }
    }
}
