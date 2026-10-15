import Foundation

/// A menu item's keyboard equivalent as the macOS menu bar exposes it through
/// AXMenuItemCmdChar / AXMenuItemCmdModifiers.
public struct MenuShortcut: Codable, Equatable, Sendable {
    public let key: String
    /// AX bit mask: 1 Shift, 2 Option, 4 Control, 8 = no Command.
    public let modifiers: Int
    public init?(key: String, modifiers: Int) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 3 else { return nil }
        self.key = trimmed; self.modifiers = modifiers
    }
    /// macOS order: ⌃⌥⇧⌘ then the key.
    public var display: String {
        var result = ""
        if modifiers & 4 != 0 { result += "⌃" }
        if modifiers & 2 != 0 { result += "⌥" }
        if modifiers & 1 != 0 { result += "⇧" }
        if modifiers & 8 == 0 { result += "⌘" }
        return result + key.uppercased()
    }
}

/// What the large area of a menu tile shows: the user's chosen SF Symbol,
/// otherwise a built-in default for a few common titles, otherwise the keyboard
/// shortcut, otherwise the title as a Windows 8 style text tile. Public AX
/// exposes no menu-item image, so the app's own menu icon is not available.
public enum MenuTileGlyph: Equatable, Sendable {
    case symbol(String)
    case shortcut(String)
    case text

    /// `symbol`/`preset` must already be validated by the caller (installed SF Symbols).
    /// `symbol == MenuSymbolName.hidden` turns off the preset as well.
    public static func resolve(symbol: String?, preset: String? = nil, shortcut: MenuShortcut?) -> Self {
        if symbol != MenuSymbolName.hidden,
           let chosen = MenuSymbolName.normalized(symbol) ?? MenuSymbolName.normalized(preset) {
            return .symbol(chosen)
        }
        if let shortcut { return .shortcut(shortcut.display) }
        return .text
    }
}

public enum MenuSymbolName {
    /// Stored when the user chose “no icon”, so a built-in default is not used either.
    public static let hidden = ""
    /// Trimmed SF Symbol name, or nil for an empty value. Names are lowercase
    /// dot-separated words such as `folder.badge.plus`.
    public static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              trimmed.count <= 80,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }) else { return nil }
        return trimmed
    }
    /// A stored choice: nil = default, `hidden` = no icon, otherwise a normalized name.
    public static func stored(_ name: String?) -> String? {
        name == hidden ? hidden : normalized(name)
    }
}

/// Built-in icons for a few common menu titles (R186). Exact title match only,
/// English or Korean macOS wording; the user's own choice always wins.
public enum MenuSymbolPreset {
    private static let symbols: [String: String] = [
        "new tab": "plus.square.on.square", "새로운 탭": "plus.square.on.square", "새 탭": "plus.square.on.square",
        "new folder": "folder.badge.plus", "새로운 폴더": "folder.badge.plus", "새 폴더": "folder.badge.plus",
        "new window": "macwindow.badge.plus", "새로운 윈도우": "macwindow.badge.plus", "새 윈도우": "macwindow.badge.plus",
        "새 창": "macwindow.badge.plus",
        "get info": "info.circle", "정보 가져오기": "info.circle",
        "go to folder": "folder", "폴더로 이동": "folder",
        "connect to server": "server.rack", "서버에 연결": "server.rack",
        "hide sidebar": "sidebar.left", "show sidebar": "sidebar.left",
        "사이드바 가리기": "sidebar.left", "사이드바 보기": "sidebar.left"
    ]
    public static func symbol(for title: String) -> String? {
        let key = title.lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return symbols[key]
    }
}
