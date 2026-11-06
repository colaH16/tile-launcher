import Foundation

/// Complete structure/title enumeration for resolving Help results. This layer
/// never reads shortcuts, identifiers, actions, search text or document values.
/// Incomplete outcomes deliberately contain no partial entries.
public enum MenuCatalogTraversal {
    public enum Read<Value> {
        case value(Value)
        case unavailable
        case failure
    }
    public enum Role: Equatable {
        case menuBarItem, menuItem, container
    }
    public enum Attribute: Equatable {
        case roots, role, title, children
    }
    public enum Failure: Equatable {
        case invalidLimits, cancelled, deadline, nodeLimit, depthLimit, childLimit
        case unavailable(Attribute), readFailure(Attribute)
        case invalidRootRole, unnamedBranch
    }
    public struct Root<Node> {
        public let node: Node
        /// The native adapter proves the system Apple root (for example by its
        /// standard AXMenuBar ancestry/index); a title alone is not that proof.
        public let isAppleMenu: Bool
        public init(node: Node, isAppleMenu: Bool = false) {
            self.node = node; self.isAppleMenu = isAppleMenu
        }
    }
    public struct Entry<Node> {
        public let node: Node
        public let path: [String]
        public init(node: Node, path: [String]) { self.node = node; self.path = path }
    }
    public struct Limits {
        public let nodes: Int
        public let children: Int
        /// Valid depths are 0..<depth, including structural containers.
        public let depth: Int
        public init(nodes: Int = 800, children: Int = 100, depth: Int = 12) {
            self.nodes = nodes; self.children = children; self.depth = depth
        }
    }
    public struct Statistics: Equatable {
        public internal(set) var nodes = 0
        public internal(set) var maximumDepth = 0
        public internal(set) var maximumChildren = 0
        public internal(set) var rootReads = 0
        public internal(set) var roleReads = 0
        public internal(set) var titleReads = 0
        public internal(set) var childrenReads = 0
    }
    public enum Outcome<Node> {
        case complete([Entry<Node>], Statistics)
        case incomplete(Failure, Statistics)
    }

    /// The adapter supplies actual role/title/children results, distinguishing
    /// missing attributes from IPC errors. Unknown roles must be `.failure`.
    /// `.container` is only for native roles known to be structural, such as
    /// AXMenu: its optional title is never queried. Missing children is not
    /// automatically a leaf; the adapter may return `.value([])` only when it
    /// has evidence of valid childlessness, never after an IPC/type failure.
    public static func scan<Node>(roots: () -> Read<[Root<Node>]>,
                                  role: (Node) -> Read<Role>,
                                  title: (Node) -> Read<String>,
                                  children: (Node) -> Read<[Node]>,
                                  hasTime: () -> Bool,
                                  isCancelled: () -> Bool,
                                  limits: Limits = .init()) -> Outcome<Node> {
        var statistics = Statistics()
        guard limits.nodes > 0, limits.children > 0, limits.depth > 0 else {
            return .incomplete(.invalidLimits, statistics)
        }
        var failure: Failure?
        var entries: [Entry<Node>] = []

        func checkpoint() -> Bool {
            guard failure == nil else { return false }
            if isCancelled() { failure = .cancelled; return false }
            if !hasTime() { failure = .deadline; return false }
            return true
        }
        func read<Value>(_ attribute: Attribute, _ operation: () -> Read<Value>) -> Value? {
            guard checkpoint() else { return nil }
            switch attribute {
            case .roots: statistics.rootReads += 1
            case .role: statistics.roleReads += 1
            case .title: statistics.titleReads += 1
            case .children: statistics.childrenReads += 1
            }
            let result = operation()
            // An IPC that crossed the deadline or a cancellation is not a
            // successful snapshot, even when it eventually returned a value.
            guard checkpoint() else { return nil }
            switch result {
            case .value(let value): return value
            case .unavailable: failure = .unavailable(attribute)
            case .failure: failure = .readFailure(attribute)
            }
            return nil
        }
        func validChildren(_ count: Int) -> Bool {
            statistics.maximumChildren = max(statistics.maximumChildren, count)
            guard count <= limits.children else { failure = .childLimit; return false }
            return true
        }
        func visit(_ node: Node, path: [String], depth: Int, root: Bool) {
            guard checkpoint() else { return }
            statistics.maximumDepth = max(statistics.maximumDepth, depth)
            guard statistics.nodes < limits.nodes else { failure = .nodeLimit; return }
            guard depth < limits.depth else { failure = .depthLimit; return }
            statistics.nodes += 1
            guard let kind = read(.role, { role(node) }) else { return }
            guard !root || kind == .menuBarItem else { failure = .invalidRootRole; return }

            let next: [String]
            let name: String?
            switch kind {
            case .container:
                name = nil
                next = path
            case .menuBarItem, .menuItem:
                guard let value = read(.title, { title(node) }) else { return }
                name = value
                next = value.isEmpty ? path : path + [value]
            }
            // Apply exclusions by the first named root only. An app command
            // named Help inside File is still enumerated with its full path.
            if next.first.map(MenuCapturePolicy.isHelpMenuTitle) == true
                || MenuCapturePolicy.isAppleMenuPath(next) { return }
            guard let descendants = read(.children, { children(node) }), validChildren(descendants.count) else { return }
            if let name, name.isEmpty {
                // A successful empty title on a childless menu item is a
                // separator, distinct from an unavailable/failed title read.
                guard kind == .menuItem && descendants.isEmpty else { failure = .unnamedBranch; return }
                return
            }
            if kind == .menuItem && descendants.isEmpty {
                guard next.count >= 2 else { failure = .unnamedBranch; return }
                entries.append(.init(node: node, path: next))
            } else {
                for descendant in descendants {
                    visit(descendant, path: next, depth: depth + 1, root: false)
                    if failure != nil { return }
                }
            }
        }

        if let roots = read(.roots, roots), validChildren(roots.count) {
            for root in roots where !root.isAppleMenu {
                visit(root.node, path: [], depth: 0, root: true)
                if failure != nil { break }
            }
        }
        // Check even an empty tree and time spent in local normalization before
        // exposing complete entries. Caller still validates its request token.
        _ = checkpoint()
        if let failure { return .incomplete(failure, statistics) }
        return .complete(entries, statistics)
    }
}
