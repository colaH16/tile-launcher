import Foundation

public enum OverlayShortcut: Equatable {
    case pin, settings, close
    case profile(step: Int)
    case number(index: Int, command: Bool)

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
        if modifiers == .option {
            switch keyCode {
            case 7: return .pin // X
            case 13: return .close // W
            case 43: return .settings // comma
            case 0, 1: return .profile(step: -1) // A, S
            case 2, 3: return .profile(step: 1) // D, F
            default: break
            }
        }
        if modifiers == .option || modifiers == [.option, .command] {
            let numberKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
            let keypadKeys: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92, 82]
            if let index = numberKeys.firstIndex(of: keyCode) ?? keypadKeys.firstIndex(of: keyCode) {
                return .number(index: index, command: modifiers.contains(.command))
            }
        }
        return nil
    }
}
