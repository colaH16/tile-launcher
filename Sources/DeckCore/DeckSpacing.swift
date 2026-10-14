import CoreGraphics

/// Shared by window sizing and SwiftUI so complete rows remain visible.
public enum DeckSpacing {
    public static let edge: CGFloat = 24
    public static let columns: CGFloat = 24
    public static let sectionTitle: CGFloat = 12
    public static let workHeader: CGFloat = 20 + sectionTitle
    public static let shelfHeader: CGFloat = 26 + sectionTitle + 4
    public static func sections(compact: Bool) -> CGFloat { compact ? 12 : 16 }
    public static func workToShelf(compact: Bool) -> CGFloat { compact ? 4 : 16 }
    public static func chrome(compact: Bool) -> CGFloat {
        edge * 2 + (compact ? 40 : 52) + sections(compact: compact) * 2 + 18 + 4
    }
}
