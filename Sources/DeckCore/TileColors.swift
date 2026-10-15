import Foundation

public enum TileSection: String, CaseIterable, Identifiable {
    case menus, windows, registered, handoff
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .menus: return "메뉴"
        case .windows: return "최근 창"
        case .registered: return "등록 항목"
        case .handoff: return "Handoff"
        }
    }
}

/// An opaque sRGB color. Store a bounded integer rather than platform color archives.
public struct TileColor: Codable, Equatable {
    public let hex: UInt32
    public init(_ hex: UInt32) { self.hex = hex & 0xFFFFFF }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(UInt32.self)
        guard value <= 0xFFFFFF else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid RGB color"))
        }
        hex = value
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
    public var red: Double { Double((hex >> 16) & 255) / 255 }
    public var green: Double { Double((hex >> 8) & 255) / 255 }
    public var blue: Double { Double(hex & 255) / 255 }
    public func mixed(with other: Self, amount: Double) -> Self {
        let t = min(1, max(0, amount))
        func channel(_ a: Double, _ b: Double) -> UInt32 { UInt32(((a + (b - a) * t) * 255).rounded()) }
        return Self(channel(red, other.red) << 16 | channel(green, other.green) << 8 | channel(blue, other.blue))
    }
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

public struct TileColors: Codable, Equatable {
    public var menus: TileColor?
    public var windows: TileColor?
    public var registered: TileColor?
    /// R192: the Handoff tile that replaces the first recent window.
    public var handoff: TileColor?
    public init() {}
    public subscript(section: TileSection) -> TileColor? {
        get {
            switch section {
            case .menus: return menus
            case .windows: return windows
            case .registered: return registered
            case .handoff: return handoff
            }
        }
        set {
            switch section {
            case .menus: menus = newValue
            case .windows: windows = newValue
            case .registered: registered = newValue
            case .handoff: handoff = newValue
            }
        }
    }
    public func seed(for section: TileSection, theme: DeckTheme) -> TileColor {
        if let color = self[section] { return color }
        switch section {
        case .menus: return TileColor(theme.isClassic ? 0x247758 : 0xD6AD41)
        case .windows: return TileColor(0x236A9C)
        case .registered: return TileColor(0x8068AC)
        case .handoff: return TileColor(0x0E9F9A)
        }
    }
    public static func restore(_ data: Data?) -> Self {
        data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
}

/// Shared by real tiles and appearance previews; tile size never changes its color.
public struct TileSurfaceColors {
    public let fill: TileColor
    public let ink: TileColor
    public let secondary: TileColor
    public init(section: TileSection, emphasized: Bool, dark: Bool, theme: DeckTheme, colors: TileColors) {
        let seed = colors.seed(for: section, theme: theme)
        let white = TileColor(0xFFFFFF)
        if emphasized {
            fill = theme.isClassic ? seed : seed.mixed(with: white, amount: dark ? 0.56 : 0.72)
        } else {
            // Lift the selected hue with white instead of muddying it with dark gray.
            // Classic keeps its strong solid accents; glass uses a lighter pastel range.
            fill = seed.mixed(with: white, amount: dark ? (theme.isClassic ? 0.50 : 0.76)
                                                        : (theme.isClassic ? 0.84 : 0.91))
        }
        let black = TileColor(0x101820)
        // Pure black is the fallback around middle luminances where off-black loses contrast.
        let darkInk = fill.contrast(with: black) >= 4.5 ? black : TileColor(0)
        ink = fill.contrast(with: darkInk) >= fill.contrast(with: white) ? darkInk : white
        let softer = ink.mixed(with: fill, amount: 0.14)
        secondary = softer.contrast(with: fill) >= 4.5 ? softer : ink
    }
}
