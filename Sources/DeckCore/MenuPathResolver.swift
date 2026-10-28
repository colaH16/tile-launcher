import Foundation

public enum MenuPathResolution<Node> {
    case found(Node), missing, ambiguous, unavailable
}

/// Resolve complete language paths independently. A German leaf cannot be
/// paired with a Korean parent merely because each word is an allowed alias.
public enum MenuPathResolver {
    public static func resolve<Node>(paths: [[String]], root: Node,
        children: (Node) -> [Node]?, title: (Node) -> String?, equal: (Node, Node) -> Bool,
        preferredIdentifier: String? = nil,
        identifier: ((Node) -> (identifier: String?, known: Bool))? = nil) -> MenuPathResolution<Node> {
        if let preferredIdentifier, MenuAXIdentifier.validated(preferredIdentifier) == nil { return .unavailable }
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
                if index == path.count - 1, let preferredIdentifier {
                    // A saved identifier is mandatory even when only one leaf
                    // remains: removing one alternate must not run its sibling.
                    guard let identifier else { return .unavailable }
                    var preferred: [Node] = []
                    for node in matches {
                        let reading = identifier(node)
                        guard reading.known else { return .unavailable }
                        if reading.identifier?.utf8.elementsEqual(preferredIdentifier.utf8) == true {
                            preferred.append(node)
                        }
                    }
                    guard !preferred.isEmpty else { return .missing }
                    guard preferred.count == 1 else { return .ambiguous }
                    matches = preferred
                }
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

public enum MenuAXIdentifier {
    /// Preserve exact case and tabs (iTerm uses tabs between tag components).
    public static func validated(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 4096,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\t" }) else { return nil }
        return value
    }
}
