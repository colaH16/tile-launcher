import Foundation

public struct LauncherProfile: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var items: [PinnedItem]
    public init(id: String = UUID().uuidString, name: String, items: [PinnedItem] = []) {
        self.id = id; self.name = name; self.items = items
    }
    public static func restore(profiles: Data?, legacyPins: Data?) -> [Self] {
        if let profiles, let saved = try? JSONDecoder().decode([Self].self, from: profiles),
           !saved.isEmpty, Set(saved.map(\.id)).count == saved.count { return saved }
        let pins = legacyPins.flatMap { try? JSONDecoder().decode([PinnedItem].self, from: $0) } ?? []
        return [Self(id: "default", name: "기본", items: pins)]
    }
}

public enum NumberShortcutAssignment: String, Codable, CaseIterable, Identifiable {
    case registeredFirst, windowsFirst
    public var id: String { rawValue }
    public var title: String {
        self == .registeredFirst ? "⌥숫자: 등록 항목 · ⌥⌘숫자: 최근 창" : "⌥숫자: 최근 창 · ⌥⌘숫자: 등록 항목"
    }
    public func targetsWindows(command: Bool) -> Bool {
        self == .registeredFirst ? command : !command
    }
    public var windowPrefix: String { self == .registeredFirst ? "⌥⌘" : "⌥" }
    public var registeredPrefix: String { self == .registeredFirst ? "⌥" : "⌥⌘" }
    public static func digit(for index: Int) -> String? {
        (0..<10).contains(index) ? String((index + 1) % 10) : nil
    }
}
