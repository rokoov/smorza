import CoreGraphics

/// Sizes shared by the panel's views, in points.
enum PanelMetrics {
    static let width: CGFloat = 320
    /// Inset of every section from the panel edge.
    static let padding: CGFloat = 16
    /// App icons and device plates.
    static let iconSize: CGFloat = 28
    static let rowSpacing: CGFloat = 14
    static let rowHeight: CGFloat = 44
    /// Rows shown before the app list starts to scroll.
    static let visibleRows = 6
    /// Smallest comfortable click target for the round buttons.
    static let hitTarget: CGFloat = 28
}
