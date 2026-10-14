import Foundation
import CoreGraphics

/// Sequential packing: a later item never fills a hole before an earlier one.
public struct TilePlacement: Equatable {
    public let index: Int
    public let row: Int
    public let column: Int
    public let span: Int
}

public enum TileArrangement {
    public static func spans<App: Equatable>(for apps: [App]) -> [Int] {
        apps.indices.map { $0 == 0 || apps[$0] != apps[$0 - 1] ? 2 : 1 }
    }
    public static func place(spans: [Int], columns: Int) -> [TilePlacement] {
        let columns = max(2, columns)
        var row = 0, column = 0
        return spans.enumerated().map { index, requested in
            let span = min(columns, max(1, requested))
            if column + span > columns { row += 1; column = 0 }
            let item = TilePlacement(index: index, row: row, column: column, span: span)
            column += span
            return item
        }
    }
}

public struct DeckGeometry {
    public let unit: CGFloat
    public let menuWidth: CGFloat
    public let windowWidth: CGFloat
    public let windowColumns: Int
    public let gap: CGFloat
    public var twoRows: CGFloat { unit * 2 + gap }
    public func viewport(rows: CGFloat) -> CGFloat {
        unit * rows + gap * max(0, ceil(rows) - 1)
    }
    public init(width: CGFloat, compact: Bool, scale: CGFloat = 1) {
        gap = 8 * scale
        // Width is logical; outer margins and section gutters stay in points.
        let content = max(1, width - DeckSpacing.edge * 2 / scale)
        if compact {
            windowColumns = content < 600 ? 4 : 6
            unit = (content - CGFloat(windowColumns - 1) * 8) / CGFloat(windowColumns) * scale
            menuWidth = 0
            windowWidth = content * scale
        } else {
            // Four menu units and at least four window units. Three complete
            // rows hold at least six wide windows, with a peek at the fourth.
            let available = content - DeckSpacing.columns / scale
            let totalColumns = width < 1040 ? 8 : 10
            windowColumns = totalColumns - 4
            unit = (available - CGFloat(totalColumns - 2) * 8) / CGFloat(totalColumns) * scale
            menuWidth = unit * 4 + 24 * scale
            windowWidth = unit * CGFloat(windowColumns) + CGFloat(windowColumns - 1) * gap
        }
    }
}

public enum RecentTileSize: Equatable {
    case application, square, wide
    public var width: Int { self == .wide ? 4 : self == .square ? 2 : 1 }
    public var height: Int { self == .application ? 1 : 2 }
}

public struct RecentTilePlacement: Equatable {
    public let index: Int
    public let row: Int
    public let column: Int
    public let width: Int
    public let height: Int
}

/// Fill two-module row bands left to right. Adjacent small tiles share a column;
/// unused cells in a completed column or band are never backfilled.
public enum RecentTileArrangement {
    public static func visible(_ placements: [RecentTilePlacement], module: CGFloat, gap: CGFloat,
                               offset: CGFloat, viewport: CGFloat) -> [RecentTilePlacement] {
        let stride = module + gap
        let lower = max(0, offset - stride * 2)
        let upper = offset + viewport + stride * 2
        return placements.filter {
            let top = CGFloat($0.row) * stride
            return top < upper && top + CGFloat($0.height) * stride - gap > lower
        }
    }
    public static func sizes<App: Equatable>(apps: [App], applications: [Bool], consecutiveSmall: Bool = false) -> [RecentTileSize] {
        precondition(apps.count == applications.count)
        return apps.indices.map { index in
            if applications[index] { return .application }
            let startsApp = index == 0 || apps[index] != apps[index - 1] || applications[index - 1]
            if consecutiveSmall { return startsApp ? .square : .application }
            return startsApp ? .wide : .square
        }
    }
    public static func place(sizes: [RecentTileSize], columns: Int) -> [RecentTilePlacement] {
        let columns = max(4, columns)
        var band = 0, column = 0
        var pendingSmallColumn: Int?
        return sizes.enumerated().map { index, size in
            if size == .application, let smallColumn = pendingSmallColumn {
                pendingSmallColumn = nil
                return RecentTilePlacement(index: index, row: band + 1, column: smallColumn, width: 1, height: 1)
            }
            pendingSmallColumn = nil
            if column + size.width > columns { band += 2; column = 0 }
            let item = RecentTilePlacement(index: index, row: band, column: column, width: size.width, height: size.height)
            if size == .application { pendingSmallColumn = column }
            column += size.width
            return item
        }
    }
}
