import Foundation

/// Symbol code or original vector/bitmap data, never a live path into an app.
public struct MenuResourceIcon: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case symbol, pdf, png }
    public let kind: Kind
    public let digest: String
    public let template: Bool
    public let sourceAppID: String
    public let sourceAppName: String
    public let resourceName: String
    public init(kind: Kind, digest: String, template: Bool, sourceAppID: String, sourceAppName: String, resourceName: String) {
        self.kind = kind
        self.digest = digest; self.template = template
        self.sourceAppID = sourceAppID; self.sourceAppName = sourceAppName; self.resourceName = resourceName
    }
    public var validDigest: Bool {
        digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

public struct MenuIconCandidate: Codable, Equatable, Sendable {
    public let title: String
    public let parent: String?
    public let icon: MenuResourceIcon
    public init(title: String, parent: String?, icon: MenuResourceIcon) {
        self.title = title; self.parent = parent; self.icon = icon
    }
}

public enum MenuIconMatch {
    /// No translation, substring search, or ellipsis stripping: “Open” and
    /// “Open…” may be different actions. Only Unicode/case/whitespace normalize.
    public static func key(_ title: String) -> String {
        title.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public static func resolve(appID: String, path: [String], candidates: [MenuIconCandidate]) -> MenuResourceIcon? {
        guard let title = path.last, !key(title).isEmpty else { return nil }
        let matches = candidates.filter { key($0.title) == key(title) && $0.icon.validDigest }
        let own = matches.filter { $0.icon.sourceAppID == appID }
        if !own.isEmpty {
            let parent = path.dropLast().last.map(key)
            let exact = own.filter { parent != nil && $0.parent.map(key) == parent }
            // Ambiguous own-app matches must not be masked by a borrowed icon.
            return unique(exact.isEmpty ? own : exact)
        }
        return unique(matches)
    }
    private static func unique(_ candidates: [MenuIconCandidate]) -> MenuResourceIcon? {
        guard let first = candidates.sorted(by: { $0.icon.sourceAppID < $1.icon.sourceAppID }).first,
              candidates.allSatisfy({ $0.icon.kind == first.icon.kind && $0.icon.digest == first.icon.digest && $0.icon.template == first.icon.template }) else { return nil }
        return first.icon
    }
}
