import CoreGraphics

/// Shared by window sizing and SwiftUI so complete rows remain visible.
public enum DeckSpacing {
    public static let edge: CGFloat = 24
    public static let columns: CGFloat = 24
    public static let sectionTitle: CGFloat = 12
    public static let toolbarTop: CGFloat = 8
    public static let toolbarBottom: CGFloat = 12
    public static let toolbarHorizontal: CGFloat = 12
    public static let toolbarButton: CGFloat = 32
    // Tile scale never changes toolbar/section controls or their line heights.
    public static func workHeader(scale _: CGFloat = 1) -> CGFloat { 20 + sectionTitle }
    public static func shelfHeader(scale _: CGFloat = 1) -> CGFloat { 26 + sectionTitle + 4 }
    public static func sections(compact: Bool) -> CGFloat { compact ? 12 : 16 }
    public static func workToShelf(compact: Bool) -> CGFloat { compact ? 4 : 16 }
    public static func headerContent(compact _: Bool, scale _: CGFloat = 1) -> CGFloat {
        toolbarButton
    }
    public static func header(compact: Bool, scale: CGFloat = 1) -> CGFloat {
        toolbarTop + headerContent(compact: compact, scale: scale) + toolbarBottom
    }
    public static func chrome(compact: Bool, scale: CGFloat = 1) -> CGFloat {
        header(compact: compact, scale: scale) + sections(compact: compact) + 18 + edge + 4
    }
}
