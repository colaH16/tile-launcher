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

/// Equivalent names of the same menu item across the stored languages.
/// Keys and values are normalized like `MenuIconMatch.key`.
public enum MenuAliasIndex {
    /// `items` are (base title, localization key); each table maps keys to a language's titles.
    public static func build(items: [(title: String, key: String?)], tables: [[String: String]],
                             limit: Int = 20_000) -> [String: [String]] {
        var groups: [String: Set<String>] = [:]
        for item in items {
            var names: Set<String> = [item.title]
            if let key = item.key { for table in tables { if let name = table[key], !name.isEmpty { names.insert(name) } } }
            guard names.count > 1 else { continue }
            for name in names {
                let normalized = MenuIconMatch.key(name)
                guard groups[normalized] != nil || groups.count < limit else { continue }
                groups[normalized, default: []].formUnion(names)
            }
        }
        return groups.mapValues { $0.sorted() }
    }
    /// Other-language names for each level of `path`, or nil when nothing is known.
    public static func aliases(for path: [String], in index: [String: [String]]) -> [[String]]? {
        let levels = path.map { title in (index[MenuIconMatch.key(title)] ?? []).filter { $0 != title } }
        return levels.contains { !$0.isEmpty } ? levels : nil
    }
}

/// Matches a menu path against a stored command, allowing each level to be the
/// stored title or one of its language aliases. Used for execution and capture
/// after an app's language changes; ambiguity is handled by the callers.
public enum MenuPathMatch {
    public static func names(_ command: MenuCommand, level: Int) -> Set<String> {
        guard command.path.indices.contains(level) else { return [] }
        let aliases = command.pathAliases.flatMap { $0.indices.contains(level) ? $0[level] : nil } ?? []
        return Set(([command.path[level]] + aliases).map(MenuIconMatch.key))
    }
    public static func matches(_ path: [String], _ command: MenuCommand) -> Bool {
        path.count == command.path.count
            && path.indices.allSatisfy { names(command, level: $0).contains(MenuIconMatch.key(path[$0])) }
    }
}
