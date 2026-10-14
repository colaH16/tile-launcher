import CoreGraphics

/// Count occupied large-row bands after actual packing, including an odd small
/// tile in the last band. Menus and windows share the larger visible height.
public enum WorkAreaRows {
    public static func visible(menuSpans: [Int], windowSizes: [RecentTileSize],
                               windowColumns: Int, compact: Bool) -> CGFloat {
        let menuRows = compact ? 0 : (TileArrangement.place(spans: menuSpans, columns: 4).last.map { $0.row + 1 } ?? 0)
        let placements = RecentTileArrangement.place(sizes: windowSizes, columns: windowColumns * 2)
        let modules = placements.map { $0.row + $0.height }.max() ?? 0
        let rows = max(1, menuRows, (modules + 1) / 2)
        return rows > 3 ? 3.3 : CGFloat(rows)
    }
}
