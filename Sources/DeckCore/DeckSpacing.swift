import CoreGraphics

/// Shared by window sizing and SwiftUI so complete rows remain visible.
public enum DeckSpacing {
    public static let edge: CGFloat = 24
    public static let columns: CGFloat = 24
    public static let sectionTitle: CGFloat = 12
    public static func workHeader(scale: CGFloat = 1) -> CGFloat { 20 * scale + sectionTitle }
    public static func shelfHeader(scale: CGFloat = 1) -> CGFloat { 26 * scale + sectionTitle + 4 }
    public static func sections(compact: Bool) -> CGFloat { compact ? 12 : 16 }
    public static func workToShelf(compact: Bool) -> CGFloat { compact ? 4 : 16 }
    public static func headerContent(compact: Bool, scale: CGFloat = 1) -> CGFloat {
        max(compact ? 40 : 52, 34 * scale)
    }
    public static func header(compact: Bool, scale: CGFloat = 1) -> CGFloat {
        edge + headerContent(compact: compact, scale: scale) + sections(compact: compact)
    }
    public static func chrome(compact: Bool, scale: CGFloat = 1) -> CGFloat {
        header(compact: compact, scale: scale) + sections(compact: compact) + 18 * scale + edge + 4
    }
}
