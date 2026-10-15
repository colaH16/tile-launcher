import Foundation

public enum MenuPathResolution<Node> {
    case found(Node), missing, ambiguous, unavailable
}

/// Resolve complete language paths independently. A German leaf cannot be
/// paired with a Korean parent merely because each word is an allowed alias.
public enum MenuPathResolver {
    public static func resolve<Node>(paths: [[String]], root: Node,
        children: (Node) -> [Node]?, title: (Node) -> String?, equal: (Node, Node) -> Bool) -> MenuPathResolution<Node> {
        func follow(_ path: [String]) -> MenuPathResolution<Node> {
            var current = root
            for name in path {
                guard let nodes = children(current) else { return .unavailable }
                var matches: [Node] = []
                for node in nodes {
                    guard let text = title(node) else { return .unavailable }
                    if MenuPathMatch.same([name], [text]) { matches.append(node) }
                }
                guard !matches.isEmpty else { return .missing }
                guard matches.count == 1 else { return .ambiguous }
                current = matches[0]
            }
            return .found(current)
        }
        var found: [Node] = []
        for (index, path) in paths.enumerated() where !path.isEmpty {
            switch follow(path) {
            case .found(let node):
                if index == 0 { return .found(node) } // Original exact path wins.
                if !found.contains(where: { equal($0, node) }) { found.append(node) }
            case .missing: continue
            case .ambiguous: return .ambiguous
            case .unavailable: return .unavailable
            }
        }
        if found.count > 1 { return .ambiguous }
        return found.first.map(MenuPathResolution.found) ?? .missing
    }
}
