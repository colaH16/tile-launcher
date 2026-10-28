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
    public let sourceIdentity: MenuResourceIdentity?
    public let sourcePath: [String]?
    public init(kind: Kind, digest: String, template: Bool, sourceAppID: String, sourceAppName: String, resourceName: String, sourceIdentity: MenuResourceIdentity? = nil, sourcePath: [String]? = nil) {
        self.sourceIdentity = sourceIdentity; self.sourcePath = sourcePath
        self.kind = kind
        self.digest = digest; self.template = template
        self.sourceAppID = sourceAppID; self.sourceAppName = sourceAppName; self.resourceName = resourceName
    }
    public var validDigest: Bool {
        digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

public struct MenuIconCandidate: Codable, Equatable, Sendable {
    public let path: [String]
    public let identity: MenuResourceIdentity
    public let icon: MenuResourceIcon
    public init(path: [String], identity: MenuResourceIdentity, icon: MenuResourceIcon) {
        self.path = path; self.identity = identity; self.icon = icon
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
        guard path.count >= 2 else { return nil }
        let matches = candidates.filter { MenuPathMatch.same($0.path, path) && $0.icon.validDigest }
        let own = matches.filter { $0.identity.appID == appID }
        if !own.isEmpty {
            guard Set(own.map(\.identity)).count == 1 else { return nil }
            return unique(own)
        }
        // Borrow only an unambiguous picture for the same whole path. This is
        // image reuse, never a binding to the donor's executable menu identity.
        return unique(matches)
    }
    private static func unique(_ candidates: [MenuIconCandidate]) -> MenuResourceIcon? {
        guard let first = candidates.sorted(by: { $0.icon.sourceAppID < $1.icon.sourceAppID }).first,
              candidates.allSatisfy({ $0.icon.kind == first.icon.kind && $0.icon.digest == first.icon.digest && $0.icon.template == first.icon.template }) else { return nil }
        return first.icon
    }
}
