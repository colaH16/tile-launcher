import Foundation

public enum OverlayShortcut: Equatable {
    case pin, settings, close

    public struct Modifiers: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let option = Self(rawValue: 1 << 0)
        public static let command = Self(rawValue: 1 << 1)
        public static let shift = Self(rawValue: 1 << 2)
        public static let control = Self(rawValue: 1 << 3)
        public static let function = Self(rawValue: 1 << 4)
    }

    /// Hardware key positions also work while a Korean input source is selected.
    /// Only called for a local event addressed to the overlay's key window.
    public static func resolve(keyCode: UInt16, modifiers: Modifiers) -> Self? {
        if keyCode == 53 { return .close } // Escape
        let withoutOption = modifiers.subtracting(.option)
        if withoutOption == .command {
            if keyCode == 43 { return .settings } // Command-comma; Option may still be held.
            if keyCode == 13 { return .close } // Command-W
        }
        if keyCode == 7 && modifiers == .option { return .pin } // Option-X
        return nil
    }
}
