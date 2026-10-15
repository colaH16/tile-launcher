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
/// otherwise the keyboard shortcut, otherwise the title as a Windows 8 style
/// text tile. Public AX exposes no menu-item image, so there is no automatic icon.
public enum MenuTileGlyph: Equatable, Sendable {
    case symbol(String)
    case shortcut(String)
    case text

    /// `symbol` must already be validated by the caller (an installed SF Symbol).
    public static func resolve(symbol: String?, shortcut: MenuShortcut?) -> Self {
        if let symbol = MenuSymbolName.normalized(symbol) { return .symbol(symbol) }
        if let shortcut { return .shortcut(shortcut.display) }
        return .text
    }
}

public enum MenuSymbolName {
    /// Trimmed SF Symbol name, or nil for an empty value. Names are lowercase
    /// dot-separated words such as `folder.badge.plus`.
    public static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              trimmed.count <= 80,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }) else { return nil }
        return trimmed
    }
}
