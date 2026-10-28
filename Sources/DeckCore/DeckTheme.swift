import Foundation

public enum DeckTheme: String, Codable, CaseIterable, Identifiable {
    case glass, classic
    public var id: String { rawValue }
    public var isClassic: Bool { self == .classic }
    public var title: String {
        self == .glass ? "유리·파스텔" : "클래식·직각"
    }
}
