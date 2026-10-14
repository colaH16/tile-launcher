import CoreGraphics

public enum RecentWindowLocation: Equatable {
    case activeDisplay, otherVisibleDisplay, hidden, visibleUnknownDisplay, unknown

    public var size: RecentTileSize {
        switch self {
        case .activeDisplay: .wide
        case .otherVisibleDisplay, .visibleUnknownDisplay: .square
        case .hidden, .unknown: .application
        }
    }
}

/// Geometry uses one coordinate system (WindowServer/CGDisplayBounds). Neither
/// this policy nor the presentation groups or reorders the incoming window MRU.
public enum RecentWindowPolicy {
    public static func display(containing window: CGRect?, displays: [CGRect]) -> Int? {
        guard let window, !window.isNull, !window.isInfinite, !window.isEmpty,
              [window.minX, window.minY, window.width, window.height].allSatisfy(\.isFinite) else { return nil }
        var best: Int?, area: CGFloat = 0
        for (index, display) in displays.enumerated() {
            let overlap = window.intersection(display)
            let candidate = overlap.isNull ? 0 : overlap.width * overlap.height
            if candidate > area { best = index; area = candidate }
        }
        return best
    }

    public static func location(desktop: WindowDesktop, bounds: CGRect?, displays: [CGRect],
                                activeDisplay: Int?) -> RecentWindowLocation {
        switch desktop {
        case .other: return .hidden
        case .unknown: return .unknown
        case .current:
            guard let owner = display(containing: bounds, displays: displays),
                  let activeDisplay, displays.indices.contains(activeDisplay) else { return .visibleUnknownDisplay }
            return owner == activeDisplay ? .activeDisplay : .otherVisibleDisplay
        }
    }

    public static func firstAppearances<App: Hashable>(apps: [App], applications: [Bool]) -> [Bool] {
        precondition(apps.count == applications.count)
        var seen = Set<App>()
        return apps.indices.map { index in
            !applications[index] && seen.insert(apps[index]).inserted
        }
    }
}
