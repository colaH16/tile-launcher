import Foundation

/// Which of an app's localizations Tile Launcher keeps (R191): every macOS
/// preferred language, US English, the app's development language and any
/// localization in which the user's captured menus of that app are named
/// (covers a per-app language or an app that only supports one language).
public enum MenuLanguageSelection {
    public static func select(available: [String], preferred: [String], development: String?,
                              capturedIn: Set<String> = []) -> Set<String> {
        var result = Set<String>()
        for language in preferred + ["en-US", "en"] {
            guard let match = Bundle.preferredLocalizations(from: available, forPreferences: [language]).first,
                  code(match) == code(language) else { continue }
            result.insert(match)
        }
        if let development, available.contains(development) { result.insert(development) }
        return result.union(capturedIn.intersection(available))
    }
    static func code(_ identifier: String) -> String? {
        Locale(identifier: identifier.replacingOccurrences(of: "_", with: "-")).language.languageCode?.identifier
    }
}

/// Resource identity is scoped to an app, archive and the complete ancestor-key
/// chain. Display titles are never the identity key.
public struct MenuResourceIdentity: Codable, Hashable, Sendable {
    public let appID: String
    public let archive: String
    public let keys: [String]
    public init(appID: String, archive: String, keys: [String]) {
        self.appID = appID; self.archive = archive; self.keys = keys
    }
}

/// Whole paths in individual languages, never independent per-level synonyms.
public struct MenuResourceBinding: Codable, Equatable, Sendable {
    public let identity: MenuResourceIdentity
    public let paths: [[String]]
    public init(identity: MenuResourceIdentity, paths: [[String]]) {
        self.identity = identity; self.paths = paths
    }
}

public enum MenuResourceMatch {
    public static func binding(appID: String, path: [String], entries: [MenuResourceBinding]) -> MenuResourceBinding? {
        let own = entries.filter { $0.identity.appID == appID }
        let matches = own.filter { $0.paths.contains { MenuPathMatch.same($0, path) } }
        guard Set(matches.map(\.identity)).count == 1, let first = matches.first else { return nil }
        // Even a translation of a uniquely identified item is unsafe if that
        // translated path is also used by another item in this catalog.
        let paths = own.filter { $0.identity == first.identity }.flatMap(\.paths).filter { translated in
            !own.contains { $0.identity != first.identity && $0.paths.contains { MenuPathMatch.same($0, translated) } }
        }
        return MenuResourceBinding(identity: first.identity, paths: MenuPathMatch.unique(paths))
    }
}

public enum MenuPathMatch {
    public static func key(_ path: [String]) -> [String] {
        path.map(\.precomposedStringWithCanonicalMapping)
    }
    public static func same(_ lhs: [String], _ rhs: [String]) -> Bool { key(lhs) == key(rhs) }
    public static func unique(_ paths: [[String]]) -> [[String]] {
        var seen = Set<[String]>()
        return paths.filter { seen.insert(key($0)).inserted }
    }
    public static func paths(_ command: MenuCommand) -> [[String]] {
        guard let binding = command.resourceBinding, binding.identity.appID == command.appID,
              !binding.identity.archive.isEmpty, (2...12).contains(binding.identity.keys.count),
              binding.paths.count <= 128,
              binding.paths.allSatisfy({ (2...12).contains($0.count) && $0.allSatisfy { !$0.isEmpty && $0.count <= 256 } }),
              binding.paths.contains(where: { same($0, command.path) }) else { return [command.path] }
        return unique([command.path] + binding.paths)
    }
    public static func matches(_ path: [String], _ command: MenuCommand) -> Bool {
        paths(command).contains { same($0, path) }
    }
}
