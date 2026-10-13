import Foundation

public struct MenuCommand: Codable, Equatable, Identifiable {
    public var id: UUID
    public let appID: String
    public let appName: String
    public let path: [String]
    public var isPinned: Bool
    public var useCount: Int
    public var lastUsed: Date?
    public var isAutomatic: Bool
    public var observedCount: Int
    // Three timestamps are sufficient for the fixed >=3 frequency threshold,
    // even when the user changes the lookback period. No unbounded event log.
    public private(set) var recentUses: [Date]
    public var title: String { path.last ?? "" }
    public var isWide: Bool { isWide(history: .init()) }
    public func isWide(history: MenuHistoryPreferences, at now: Date = Date()) -> Bool {
        isPinned || isFrequent(history: history, at: now)
    }
    public func isFrequent(history: MenuHistoryPreferences, at now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(history.frequentDays) * 86_400)
        return recentUses.filter { $0 >= cutoff && $0 <= now }.count >= 3
    }
    public mutating func recordUse(at date: Date, observed: Bool = false) {
        if observed { observedCount = min(Int.max - 1, observedCount) + 1 }
        else { useCount = min(Int.max - 1, useCount) + 1 }
        lastUsed = max(lastUsed ?? date, date)
        recentUses = Array((recentUses + [date]).sorted(by: >).prefix(3))
    }
    public init(appID: String, appName: String, path: [String], isPinned: Bool = true) {
        id = UUID()
        self.appID = appID; self.appName = appName; self.path = path
        self.isPinned = isPinned; useCount = 0; lastUsed = nil
        isAutomatic = false; observedCount = 0; recentUses = []
    }
    private enum CodingKeys: String, CodingKey {
        case id, appID, appName, path, isPinned, useCount, lastUsed, isAutomatic, observedCount, recentUses
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appID = try c.decode(String.self, forKey: .appID)
        appName = try c.decode(String.self, forKey: .appName)
        path = try c.decode([String].self, forKey: .path)
        isPinned = try c.decode(Bool.self, forKey: .isPinned)
        useCount = max(0, try c.decode(Int.self, forKey: .useCount))
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
        isAutomatic = try c.decodeIfPresent(Bool.self, forKey: .isAutomatic) ?? false
        observedCount = max(0, try c.decodeIfPresent(Int.self, forKey: .observedCount) ?? 0)
        if let dates = try c.decodeIfPresent([Date].self, forKey: .recentUses) {
            recentUses = Array(dates.sorted(by: >).prefix(3))
        } else {
            // Old counters have no dates. Only the last use is known; never
            // invent multiple recent uses from a lifetime count.
            recentUses = (useCount > 0 || observedCount > 0) ? lastUsed.map { [$0] } ?? [] : []
        }
    }
    /// Storage order is the manual order within pinned/frequent groups.
    public static func ordered(_ commands: [Self], appID: String,
                               history: MenuHistoryPreferences = .init(), at now: Date = Date(),
                               includingHidden: Bool = false) -> [Self] {
        let peers = commands.enumerated().filter { $0.element.appID == appID }
        let recent = peers.filter { !$0.element.isPinned && $0.element.lastUsed != nil }.sorted {
            if $0.element.lastUsed != $1.element.lastUsed { return $0.element.lastUsed! > $1.element.lastUsed! }
            return $0.offset < $1.offset
        }
        let retained = Set(recent.prefix(5).map { $0.element.id })
        let cutoff = now.addingTimeInterval(-Double(history.recentDays) * 86_400)
        return peers.filter {
            let command = $0.element
            return includingHidden || command.isWide(history: history, at: now) || retained.contains(command.id)
                || command.lastUsed.map { $0 >= cutoff } == true || (!command.isAutomatic && command.lastUsed == nil)
        }.sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let ag = a.isPinned ? 0 : a.isWide(history: history, at: now) ? 1 : 2
            let bg = b.isPinned ? 0 : b.isWide(history: history, at: now) ? 1 : 2
            if ag != bg { return ag < bg }
            if ag == 2 && a.lastUsed != b.lastUsed {
                return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
    public static func frequentIDs(_ commands: [Self], appID: String,
                                   history: MenuHistoryPreferences = .init(), at now: Date = Date()) -> Set<UUID> {
        Set(commands.filter { $0.appID == appID && $0.isFrequent(history: history, at: now) }.map(\.id))
    }
}
