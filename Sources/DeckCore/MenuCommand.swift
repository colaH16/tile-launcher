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
    /// Last keyboard equivalent seen in the app's menu bar, if any.
    public var shortcut: MenuShortcut?
    /// The selected AXIdentifier; checked within this app and a complete path.
    public var axIdentifier: String?
    public var optionAction: MenuActionReference?
    public var executionSelection: MenuExecutionSelection { .init(identifier: axIdentifier, option: optionAction) }
    public func optionCommand() -> MenuCommand? {
        guard let optionAction, optionAction.isValid else { return nil }
        var action = MenuCommand(appID: appID, appName: appName, path: optionAction.path, isPinned: isPinned)
        action.id = id; action.axIdentifier = optionAction.identifier
        return action
    }
    /// User-chosen SF Symbol for the overlay tile: nil = built-in default,
    /// `MenuSymbolName.hidden` = no icon.
    public var symbol: String?
    /// Automatically acquired image; a user's symbol/no-icon choice still wins.
    public var resourceIcon: MenuResourceIcon?
    /// Legacy title-only aliases: decoded for compatibility, never executed.
    public var pathAliases: [[String]]?
    public var resourceBinding: MenuResourceBinding?
    public var resourceIdentityVersion: Int?
    /// Shared matching hint; execution still requires a binding verified on this Mac.
    public var syncResourceIdentity: MenuResourceIdentity?
    public var title: String { path.last ?? "" }
    public var totalUseCount: Int {
        let (total, overflow) = useCount.addingReportingOverflow(observedCount)
        return overflow ? Int.max : total
    }
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
        case id, appID, appName, path, isPinned, useCount, lastUsed, isAutomatic, observedCount, recentUses, shortcut, axIdentifier, optionAction, symbol, resourceIcon, pathAliases, resourceBinding, resourceIdentityVersion, syncResourceIdentity
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appID = try c.decode(String.self, forKey: .appID)
        appName = try c.decode(String.self, forKey: .appName)
        // Cache metadata is expendable; an unknown/corrupt icon must never make
        // the user's menu list fail to decode.
        resourceIcon = try? c.decodeIfPresent(MenuResourceIcon.self, forKey: .resourceIcon)
        pathAliases = try? c.decodeIfPresent([[String]].self, forKey: .pathAliases)
        resourceBinding = try? c.decodeIfPresent(MenuResourceBinding.self, forKey: .resourceBinding)
        resourceIdentityVersion = try? c.decodeIfPresent(Int.self, forKey: .resourceIdentityVersion)
        syncResourceIdentity = try? c.decodeIfPresent(MenuResourceIdentity.self, forKey: .syncResourceIdentity)
        path = try c.decode([String].self, forKey: .path)
        isPinned = try c.decode(Bool.self, forKey: .isPinned)
        useCount = max(0, try c.decode(Int.self, forKey: .useCount))
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
        isAutomatic = try c.decodeIfPresent(Bool.self, forKey: .isAutomatic) ?? false
        observedCount = max(0, try c.decodeIfPresent(Int.self, forKey: .observedCount) ?? 0)
        shortcut = try? c.decodeIfPresent(MenuShortcut.self, forKey: .shortcut)
        axIdentifier = try? c.decodeIfPresent(String.self, forKey: .axIdentifier)
        optionAction = try? c.decodeIfPresent(MenuActionReference.self, forKey: .optionAction)
        symbol = MenuSymbolName.stored(try? c.decodeIfPresent(String.self, forKey: .symbol))
        if let dates = try c.decodeIfPresent([Date].self, forKey: .recentUses) {
            recentUses = Array(dates.sorted(by: >).prefix(3))
        } else {
            // Old counters have no dates. Only the last use is known; never
            // invent multiple recent uses from a lifetime count.
            recentUses = (useCount > 0 || observedCount > 0) ? lastUsed.map { [$0] } ?? [] : []
        }
    }
    /// Storage order is manual only for pinned menus; all other entries use counts.
    /// Preserve stored history and intentional pins, but hide previously learned
    /// system commands from recent/frequent app menus.
    private var hiddenSystemCapture: Bool {
        isAutomatic && !isPinned && MenuCapturePolicy.isAppleMenuPath(path)
    }
    public static func ordered(_ commands: [Self], appID: String,
                               history: MenuHistoryPreferences = .init(), at now: Date = Date(),
                               includingHidden: Bool = false) -> [Self] {
        let peers = commands.enumerated().filter {
            $0.element.appID == appID && (includingHidden || !$0.element.hiddenSystemCapture)
        }
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
            if a.isPinned != b.isPinned { return a.isPinned }
            if !a.isPinned {
                if a.totalUseCount != b.totalUseCount { return a.totalUseCount > b.totalUseCount }
                if a.lastUsed != b.lastUsed {
                    return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
                }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
    public struct MoveTargets {
        public var previous: UUID?
        public var next: UUID?
    }
    /// Compute both arrows in one pass. Frequency never grants manual ordering.
    public static func pinnedMoveTargets(in commands: [Self]) -> [UUID: MoveTargets] {
        var result: [UUID: MoveTargets] = [:]
        var last: [String: UUID] = [:]
        for command in commands where command.isPinned {
            let previous = last[command.appID]
            result[command.id] = MoveTargets(previous: previous, next: nil)
            if let previous { result[previous]?.next = command.id }
            last[command.appID] = command.id
        }
        return result
    }
    public static func pinnedMoveTarget(for id: UUID, by offset: Int, in commands: [Self]) -> UUID? {
        guard offset == -1 || offset == 1 else { return nil }
        let targets = pinnedMoveTargets(in: commands)[id]
        return offset == -1 ? targets?.previous : targets?.next
    }
    public static func frequentIDs(_ commands: [Self], appID: String,
                                   history: MenuHistoryPreferences = .init(), at now: Date = Date()) -> Set<UUID> {
        Set(commands.filter { $0.appID == appID && !$0.hiddenSystemCapture && $0.isFrequent(history: history, at: now) }.map(\.id))
    }
}
