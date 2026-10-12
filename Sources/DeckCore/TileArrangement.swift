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
    public let gap: CGFloat = 8
    public var twoRows: CGFloat { unit * 2 + gap }
    public func viewport(rows: CGFloat) -> CGFloat {
        unit * rows + gap * max(0, ceil(rows) - 1)
    }
    public init(width: CGFloat, compact: Bool) {
        let content = max(1, width - 48)
        if compact {
            windowColumns = max(6, Int((content + 8) / 70) / 2 * 2)
            unit = (content - CGFloat(windowColumns - 1) * 8) / CGFloat(windowColumns)
            menuWidth = 0
            windowWidth = content
        } else {
            // Four menu units; at least six window units (six wide windows in two rows).
            let available = content - 22
            let totalColumns = max(10, Int((available + 16) / 80) / 2 * 2)
            windowColumns = totalColumns - 4
            unit = (available - CGFloat(totalColumns - 2) * 8) / CGFloat(totalColumns)
            menuWidth = unit * 4 + 24
            windowWidth = unit * CGFloat(windowColumns) + CGFloat(windowColumns - 1) * 8
        }
    }
}
