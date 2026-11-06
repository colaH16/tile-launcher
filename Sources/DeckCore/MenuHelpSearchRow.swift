import Foundation

/// Help search exposes AXTable/AXRow/AXCell/AXStaticText, not pressable menu
/// items. Read only a result row proven to belong to the app's Help menu.
public enum MenuHelpSearchRow {
    public enum Role { case row, cell, table, staticText, other }
    public struct Result: Equatable {
        public let label: String
        public let frame: CGRect
    }
    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    public struct Diagnostic {
        public enum Failure: String, Encodable {
            case none, noRow, noTable, tableRole, menuPath, helpOwnership
            case rowFrame, rowChildren, cellCount, cellRole, cellChildren, contentCount
            case labelValue, labelCount
        }
        public var failure: Failure = .none
        public var helpOwned = false
        public var cellCount = 0
        public var labelCount = 0
    }
    #endif

    public static func read<Node>(from original: Node,
                                  role: (Node) -> Role,
                                  parent: (Node) -> Node?,
                                  children: (Node) -> [Node]?,
                                  staticText: (Node) -> String?,
                                  frame: (Node) -> CGRect?,
                                  menuPath: (Node) -> [String]?) -> Result? {
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        return read(from: original, role: role, parent: parent, children: children,
                    staticText: staticText, frame: frame, menuPath: menuPath, diagnostic: nil)
        #else
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
        #endif
    }

    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    /// The diagnostic build follows the same short-circuit order and invokes the
    /// same supplied readers as the normal implementation. Only reason/counts escape.
    public static func read<Node>(from original: Node,
                                  role: (Node) -> Role,
                                  parent: (Node) -> Node?,
                                  children: (Node) -> [Node]?,
                                  staticText: (Node) -> String?,
                                  frame: (Node) -> CGRect?,
                                  menuPath: (Node) -> [String]?,
                                  diagnostic: ((Diagnostic) -> Void)?) -> Result? {
        var trace = Diagnostic()
        defer { diagnostic?(trace) }
        var current: Node? = original
        var row: Node?
        for _ in 0..<6 {
            guard let node = current else { trace.failure = .noRow; return nil }
            if role(node) == .row { row = node; break }
            current = parent(node)
        }
        guard let row else { trace.failure = .noRow; return nil }
        guard let table = parent(row) else { trace.failure = .noTable; return nil }
        guard role(table) == .table else { trace.failure = .tableRole; return nil }
        guard let path = menuPath(table) else { trace.failure = .menuPath; return nil }
        guard path.count == 1, MenuCapturePolicy.isHelpMenuTitle(path[0]) else {
            trace.failure = .helpOwnership; return nil
        }
        trace.helpOwned = true
        guard let bounds = frame(row), bounds.size.width > 0, bounds.size.height > 0,
              [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else {
            trace.failure = .rowFrame; return nil
        }
        guard let cells = children(row) else { trace.failure = .rowChildren; return nil }
        trace.cellCount = cells.count
        guard !cells.isEmpty, cells.count <= 4 else { trace.failure = .cellCount; return nil }
        var labels: [String] = []
        for cell in cells {
            guard role(cell) == .cell else { trace.failure = .cellRole; return nil }
            guard let contents = children(cell) else { trace.failure = .cellChildren; return nil }
            guard contents.count <= 8 else { trace.failure = .contentCount; return nil }
            for text in contents where role(text) == .staticText {
                guard let label = staticText(text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !label.isEmpty, label.count <= 1024 else { trace.failure = .labelValue; return nil }
                labels.append(label)
                trace.labelCount = labels.count
            }
        }
        guard labels.count == 1 else { trace.failure = .labelCount; return nil }
        return Result(label: labels[0], frame: bounds)
    }
    #endif
}
