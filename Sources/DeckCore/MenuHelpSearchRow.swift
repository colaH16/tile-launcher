import Foundation

/// Help search exposes AXTable/AXRow/AXCell/AXStaticText, not pressable menu
/// items. Read only a result row proven to belong to the app's Help menu.
public enum MenuHelpSearchRow {
    public enum Role { case row, cell, table, staticText, other }
    public struct Result: Equatable {
        public let label: String
        public let frame: CGRect
    }

    public static func read<Node>(from original: Node,
                                  role: (Node) -> Role,
                                  parent: (Node) -> Node?,
                                  children: (Node) -> [Node]?,
                                  staticText: (Node) -> String?,
                                  frame: (Node) -> CGRect?,
                                  menuPath: (Node) -> [String]?) -> Result? {
        var current: Node? = original
        var row: Node?
        for _ in 0..<6 {
            guard let node = current else { return nil }
            if role(node) == .row { row = node; break }
            current = parent(node)
        }
        guard let row, let table = parent(row), role(table) == .table,
              let path = menuPath(table), path.count == 1,
              MenuCapturePolicy.isHelpMenuTitle(path[0]),
              let bounds = frame(row), bounds.size.width > 0, bounds.size.height > 0,
              [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              let cells = children(row), !cells.isEmpty, cells.count <= 4 else { return nil }
        var labels: [String] = []
        for cell in cells {
            guard role(cell) == .cell, let contents = children(cell), contents.count <= 8 else { return nil }
            // Never inspect the Help search field's value or arbitrary app text.
            for text in contents where role(text) == .staticText {
                guard let label = staticText(text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !label.isEmpty, label.count <= 1024 else { return nil }
                labels.append(label)
            }
        }
        guard labels.count == 1 else { return nil }
        return Result(label: labels[0], frame: bounds)
    }
}
