import CoreGraphics

/// Shared by the grid and its bottom shelf so a complete last row isn't clipped.
public struct RegisteredGridGeometry {
    public let columns: Int
    public let side: CGFloat
    public let gap: CGFloat = 8
    public init(width: CGFloat) {
        let content = max(1, width - 48)
        columns = max(1, Int((content + gap) / (60 + gap)))
        side = (content - CGFloat(columns - 1) * gap) / CGFloat(columns)
    }
    public func shelfHeight(count: Int, maximumRows: Int) -> CGFloat {
        let rows = min(maximumRows, max(1, (max(0, count) + columns - 1) / columns))
        return CGFloat(rows) * side + CGFloat(rows - 1) * gap + 34
    }
}

/// Allocate the registered shelf from the bottom, then position the two-row
/// work area 30% into its remaining vertical slack. Tile proportions stay fixed.
public struct DeckContentLayout {
    public let registeredHeight: CGFloat
    public let workHeight: CGFloat
    public let workTopInset: CGFloat
    public let gap: CGFloat

    public init(width: CGFloat, availableHeight: CGFloat, registeredCount: Int, compact: Bool) {
        gap = compact ? 10 : 18
        let geometry = DeckGeometry(width: width, compact: compact)
        workHeight = geometry.twoRows + 30
        let desired = RegisteredGridGeometry(width: width)
            .shelfHeight(count: registeredCount, maximumRows: compact ? 2 : 3)
        let room = max(0, availableHeight - workHeight - gap)
        registeredHeight = min(desired, room)
        workTopInset = max(0, availableHeight - registeredHeight - gap - workHeight) * 0.3
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
