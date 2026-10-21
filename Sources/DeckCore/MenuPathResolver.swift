import Foundation

public enum MenuPathResolution<Node> {
    case found(Node), missing, ambiguous, unavailable
}

/// Resolve complete language paths independently. A German leaf cannot be
/// paired with a Korean parent merely because each word is an allowed alias.
public enum MenuPathResolver {
    public static func resolve<Node>(paths: [[String]], root: Node,
        children: (Node) -> [Node]?, title: (Node) -> String?, equal: (Node, Node) -> Bool,
        preferredShortcut: MenuShortcut? = nil,
        shortcut: ((Node) -> (shortcut: MenuShortcut?, known: Bool))? = nil) -> MenuPathResolution<Node> {
        func follow(_ path: [String]) -> MenuPathResolution<Node> {
            var current = root
            for (index, name) in path.enumerated() {
                guard let nodes = children(current) else { return .unavailable }
                var matches: [Node] = []
                for node in nodes {
                    guard let text = title(node) else { return .unavailable }
                    if MenuPathMatch.same([name], [text]), !matches.contains(where: { equal($0, node) }) {
                        matches.append(node)
                    }
                }
                guard !matches.isEmpty else { return .missing }
                if matches.count > 1 {
                    // AppKit alternates can share a complete title path (e.g.
                    // iTerm profiles). Only an exact saved key equivalent may
                    // disambiguate the leaf; never guess between parent menus.
                    guard index == path.count - 1, let preferredShortcut, let shortcut else { return .ambiguous }
                    var preferred: [Node] = []
                    for node in matches {
                        let reading = shortcut(node)
                        guard reading.known else { return .unavailable }
                        if let candidate = reading.shortcut,
                           candidate.modifiers == preferredShortcut.modifiers,
                           candidate.key.caseInsensitiveCompare(preferredShortcut.key) == .orderedSame {
                            preferred.append(node)
                        }
                    }
                    guard preferred.count == 1 else { return .ambiguous }
                    matches = preferred
                }
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
