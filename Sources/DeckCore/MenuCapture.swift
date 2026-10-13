import Foundation

public struct MenuIdentity: Codable, Hashable {
    public let appID: String
    public let path: [String]
    public init(appID: String, path: [String]) { self.appID = appID; self.path = path }
}

public struct MenuCapturePreferences: Codable, Equatable {
    public var enabled = true
    public var excludedApps: Set<String> = []
    public var excludedMenus: Set<MenuIdentity> = []
    public init() {}
    public func allows(appID: String) -> Bool { enabled && !excludedApps.contains(appID) }
    public static func restore(_ data: Data?) -> Self {
        guard let data else { return Self() }
        if let decoded = try? JSONDecoder().decode(Self.self, from: data) { return decoded }
        var paused = Self()
        paused.enabled = false
        return paused
    }
}

public struct CapturedMenu: Equatable {
    public let identity: MenuIdentity
    public let appName: String
    public let shortcut: String
    public let commandModifier: Bool
    public let fromHelpSearch: Bool
    public init(appID: String, appName: String, path: [String], shortcut: String = "",
                commandModifier: Bool = false, fromHelpSearch: Bool = false) {
        identity = MenuIdentity(appID: appID, path: path); self.appName = appName
        self.shortcut = shortcut; self.commandModifier = commandModifier; self.fromHelpSearch = fromHelpSearch
    }
}

public enum MenuCapturePolicy {
    public static func isAppleMenuPath(_ path: [String]) -> Bool {
        guard let root = path.first else { return false }
        return ["apple", ""].contains(normalize(root))
    }
    public static func allows(_ menu: CapturedMenu, preferences: MenuCapturePreferences) -> Bool {
        let path = menu.identity.path
        guard preferences.allows(appID: menu.identity.appID), !preferences.excludedMenus.contains(menu.identity),
              !isAppleMenuPath(path),
              (2...12).contains(path.count), path.allSatisfy({ !$0.isEmpty && $0.count <= 256 }) else { return false }
        let normalized = path.map(normalize)
        let dynamicParents: Set<String> = ["open recent", "recent items", "recent documents", "recent folders",
            "최근 항목 열기", "최근 사용", "최근 사용 항목", "최근 항목", "최근 문서", "최근 폴더"]
        guard !normalized.dropLast().contains(where: dynamicParents.contains) else { return false }
        // Unbound leaves directly in Window are commonly changing document/window titles.
        if ["window", "윈도우", "창"].contains(normalized[0]), path.count == 2, menu.shortcut.isEmpty { return false }
        return true
    }
    public static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "").lowercased()
    }
    /// Help results are only usable when the real menu command has one exact title match.
    public static func resolveHelp(title: String, choices: [CapturedMenu]) -> CapturedMenu? {
        let matches = choices.filter { !isAppleMenuPath($0.identity.path) && normalize($0.identity.path.last ?? "") == normalize(title) }
        let unique = Dictionary(grouping: matches, by: \.identity)
        guard unique.count == 1, let match = unique.values.first?.first else { return nil }
        return CapturedMenu(appID: match.identity.appID, appName: match.appName, path: match.identity.path,
                            shortcut: match.shortcut, commandModifier: match.commandModifier, fromHelpSearch: true)
    }
}

/// Notifications can describe highlighting. A physical release/Return must arm
/// a short-lived gesture, and the native adapter must match its item/position.
public struct MenuCaptureGate {
    private var armedAt: TimeInterval?
    private var consumed = false
    public init() {}
    public mutating func arm(time: TimeInterval) { armedAt = time; consumed = false }
    public mutating func cancel() { armedAt = nil; consumed = false }
    public mutating func take(_ menu: CapturedMenu, matchedUserSelection: Bool,
                              time: TimeInterval, preferences: MenuCapturePreferences) -> CapturedMenu? {
        guard let armedAt, !consumed, time >= armedAt, time - armedAt <= 0.8,
              matchedUserSelection, MenuCapturePolicy.allows(menu, preferences: preferences) else { return nil }
        consumed = true
        return menu
    }
}

public enum MenuCaptureKeyDecision: Equatable {
    case cancel, confirm, clearHighlight
    public static func resolve(keyCode: UInt16, shortcutModifier: Bool, repeating: Bool, menuWasOpen: Bool) -> Self {
        if shortcutModifier || keyCode == 53 { return .cancel }
        if [UInt16(36), 76].contains(keyCode), !repeating, menuWasOpen { return .confirm }
        return .clearHighlight
    }
}

public enum MenuCaptureHistory {
    public static func record(_ menu: CapturedMenu, in commands: [MenuCommand], at date: Date) -> [MenuCommand] {
        guard !MenuCapturePolicy.isAppleMenuPath(menu.identity.path) else { return commands }
        var result = commands
        if let i = result.firstIndex(where: { $0.appID == menu.identity.appID && $0.path == menu.identity.path }) {
            result[i].recordUse(at: date, observed: true)
        } else {
            var command = MenuCommand(appID: menu.identity.appID, appName: menu.appName, path: menu.identity.path, isPinned: false)
            command.isAutomatic = true; command.recordUse(at: date, observed: true)
            result.append(command)
        }
        // Visibility uses the user-selected lookback OR the app-local recent five.
        // Keep compact metadata so changing the lookback can restore older items.
        return result
    }
}
