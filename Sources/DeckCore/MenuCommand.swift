import Foundation

public struct MenuCommand: Codable, Equatable, Identifiable {
    public var id: UUID
    public let appID: String
    public let appName: String
    public let path: [String]
    public var isPinned: Bool
    public var useCount: Int
    public var lastUsed: Date?
    public var title: String { path.last ?? "" }
    public var isWide: Bool { isPinned || useCount >= 3 }
    public init(appID: String, appName: String, path: [String], isPinned: Bool = true) {
        id = UUID()
        self.appID = appID; self.appName = appName; self.path = path
        self.isPinned = isPinned; useCount = 0; lastUsed = nil
    }
    /// Storage order is the manual order within pinned/frequent groups.
    public static func ordered(_ commands: [Self], appID: String) -> [Self] {
        commands.enumerated().filter { $0.element.appID == appID }.sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let ag = a.isPinned ? 0 : a.isWide ? 1 : 2
            let bg = b.isPinned ? 0 : b.isWide ? 1 : 2
            if ag != bg { return ag < bg }
            if ag == 2 && a.lastUsed != b.lastUsed {
                return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
