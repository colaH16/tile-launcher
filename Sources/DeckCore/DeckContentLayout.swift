import CoreGraphics

/// Shared by the grid and its bottom shelf so a complete last row isn't clipped.
public struct RegisteredGridGeometry {
    public let columns: Int
    public let side: CGFloat
    public let gap: CGFloat
    public init(width: CGFloat, scale: CGFloat = 1) {
        gap = DeckSpacing.tileGap(scale: scale)
        let content = max(1, width * scale - DeckSpacing.edge * 2)
        // Keep the same density as the base layout when only margins change.
        columns = max(1, Int((max(1, width - DeckSpacing.edge * 2) + 8) / (60 + 8)))
        side = (content - CGFloat(columns - 1) * gap) / CGFloat(columns)
        headerHeight = DeckSpacing.shelfHeader(scale: scale)
    }
    private let headerHeight: CGFloat
    public func shelfHeight(count: Int, maximumRows: Int) -> CGFloat {
        let rows = min(maximumRows, max(1, (max(0, count) + columns - 1) / columns))
        // AppKit rounds scroll document edges to points. Reserve that rounding
        // here too so a fully fitting grid does not lose its last pixel.
        return (CGFloat(rows) * side + CGFloat(rows - 1) * gap).rounded(.up) + headerHeight.rounded(.up) + 1
    }
}

/// Physical heights shared by the panel and the view. Prefer 3.3 recent rows
/// and the profile's registered rows. On smaller screens retain at least two
/// recent rows (one in compact mode), giving the remaining height to the shelf.
public struct DeckContentLayout {
    public let registeredHeight: CGFloat
    public let workHeight: CGFloat
    public let workTopInset: CGFloat
    public let gap: CGFloat

    public init(width: CGFloat, availableHeight: CGFloat, registeredCount: Int, compact: Bool, scale: CGFloat = 1,
                workRows: CGFloat = 3.3) {
        gap = DeckSpacing.workToShelf(compact: compact)
        let geometry = DeckGeometry(width: width, compact: compact, scale: scale)
        let grid = RegisteredGridGeometry(width: width, scale: scale)
        let oneRegisteredRow = grid.shelfHeight(count: 1, maximumRows: 1)
        let desiredShelf = grid.shelfHeight(count: registeredCount, maximumRows: compact ? 2 : 3)
        let rows = max(1, min(3.3, workRows))
        let desiredWork = (geometry.viewport(rows: rows) + DeckSpacing.workHeader(scale: scale)).rounded(.up)
        let minimumWork = geometry.viewport(rows: min(rows, compact ? 1 : 2)) + DeckSpacing.workHeader(scale: scale)
        let available = max(0, availableHeight - gap)
        registeredHeight = min(available, max(oneRegisteredRow, min(desiredShelf, available - minimumWork)))
        workHeight = min(desiredWork, max(0, available - registeredHeight))
        workTopInset = 0
    }
}

public enum WindowDesktop: String, Equatable {
    case current, other, unknown

    public static func resolve(windowSpaces: Set<UInt64>?, activeSpaces: Set<UInt64>, onScreen: Bool) -> Self {
        if let windowSpaces, !windowSpaces.isEmpty, !activeSpaces.isEmpty {
            return windowSpaces.isDisjoint(with: activeSpaces) ? .other : .current
        }
        // Offscreen is not proof of another desktop: minimized/hidden windows
        // can still belong to the active desktop.
        return onScreen ? .current : .unknown
    }
}

public enum WindowRetention {
    public static func keepMissing(serverStillContains: Bool?, axInvalid: Bool, destroyed: Bool) -> Bool {
        !destroyed && !axInvalid && serverStillContains != false
    }
}
