import Foundation

/// Apply only a user's changed fields to the latest values. Runtime menu usage
/// and newly captured commands are independent of an open settings editor.
public enum SettingsDraftMerge {
    public static func field<T: Equatable>(_ before: T, _ edited: T, _ latest: T) -> T {
        edited == before ? latest : edited
    }
    public static func set<T: Hashable>(_ before: Set<T>, _ edited: Set<T>, _ latest: Set<T>) -> Set<T> {
        latest.subtracting(before.subtracting(edited)).union(edited.subtracting(before))
    }
    static func order<ID: Hashable>(_ before: [ID], _ edited: [ID], _ latest: [ID]) -> [ID] {
        let wanted = Set(edited), original = Set(before)
        let appended = before.filter(wanted.contains) + edited.filter { !original.contains($0) }
        guard edited != appended else { return latest }
        var replacements = edited.filter(Set(latest).contains).makeIterator()
        return latest.map { wanted.contains($0) ? replacements.next()! : $0 }
    }
    public static func commands(before: [MenuCommand], edited: [MenuCommand], latest: [MenuCommand], tombstones: [UUID: MenuCommand] = [:]) -> [MenuCommand] {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let retained = Set(edited.map(\.id))
        var result = latest.filter { old[$0.id] == nil || retained.contains($0.id) }
        var positions = Dictionary(result.enumerated().map { ($0.element.id, $0.offset) },
                                   uniquingKeysWith: { first, _ in first })
        var mappedIDs: [UUID: UUID] = [:]
        for change in edited {
            if let base = old[change.id] {
                if positions[change.id] == nil {
                    guard base.isPinned != change.isPinned || base.symbol != change.symbol || base.executionSelection != change.executionSelection else { continue }
                    var restored = tombstones[change.id] ?? base
                    restored.isPinned = field(base.isPinned, change.isPinned, restored.isPinned)
                    restored.symbol = field(base.symbol, change.symbol, restored.symbol)
                    positions[change.id] = result.count; result.append(restored)
                }
                guard let index = positions[change.id] else { continue }
                var current = result[index]
                current.isPinned = field(base.isPinned, change.isPinned, current.isPinned)
                current.symbol = field(base.symbol, change.symbol, current.symbol)
                current.shortcut = field(base.shortcut, change.shortcut, current.shortcut)
                let selection = field(base.executionSelection, change.executionSelection, current.executionSelection)
                current.axIdentifier = selection.identifier; current.optionAction = selection.option
                current.resourceIcon = field(base.resourceIcon, change.resourceIcon, current.resourceIcon)
                current.resourceBinding = field(base.resourceBinding, change.resourceBinding, current.resourceBinding)
                current.resourceIdentityVersion = field(base.resourceIdentityVersion, change.resourceIdentityVersion, current.resourceIdentityVersion)
                current.pathAliases = field(base.pathAliases, change.pathAliases, current.pathAliases)
                result[index] = current
            } else if let index = MenuCaptureHistory.index(of: .init(appID: change.appID, path: change.path), in: result) {
                // A menu may have been learned after the user opened its editor.
                mappedIDs[change.id] = result[index].id
                result[index].isPinned = change.isPinned
                if let symbol = change.symbol { result[index].symbol = symbol }
                if let icon = change.resourceIcon { result[index].resourceIcon = icon }
                if !change.executionSelection.isEmpty {
                    result[index].axIdentifier = change.axIdentifier; result[index].optionAction = change.optionAction
                }
                if let binding = change.resourceBinding {
                    result[index].resourceBinding = binding
                    result[index].resourceIdentityVersion = change.resourceIdentityVersion
                }
            } else {
                positions[change.id] = result.count
                result.append(change)
            }
        }
        let ids = order(before.map(\.id), edited.map { mappedIDs[$0.id] ?? $0.id }, result.map(\.id))
        let values = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { values[$0] }
    }
}

public struct AppearanceSettingsDraft: Equatable {
    public var theme: DeckTheme
    public var colors: TileColors
    public init(theme: DeckTheme, colors: TileColors) { self.theme = theme; self.colors = colors }
    public func rebased(from before: Self, onto latest: Self) -> Self {
        var colors = latest.colors
        for section in TileSection.allCases {
            colors[section] = SettingsDraftMerge.field(before.colors[section], self.colors[section], colors[section])
        }
        return Self(theme: SettingsDraftMerge.field(before.theme, theme, latest.theme), colors: colors)
    }
}

public struct MenuSettingsDraft: Equatable {
    public var showsAppSettings: Bool
    public var capture: MenuCapturePreferences
    public var history: MenuHistoryPreferences
    public var commands: [MenuCommand]
    public init(showsAppSettings: Bool, capture: MenuCapturePreferences, history: MenuHistoryPreferences, commands: [MenuCommand]) {
        self.showsAppSettings = showsAppSettings; self.capture = capture; self.history = history; self.commands = commands
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.showsAppSettings == rhs.showsAppSettings && lhs.capture == rhs.capture && lhs.history == rhs.history
            && lhs.commands.map(EditableMenu.init) == rhs.commands.map(EditableMenu.init)
    }
    public func rebased(from before: Self, onto latest: Self, tombstones: [UUID: MenuCommand] = [:]) -> Self {
        var capture = latest.capture
        capture.enabled = SettingsDraftMerge.field(before.capture.enabled, self.capture.enabled, capture.enabled)
        capture.excludedApps = SettingsDraftMerge.set(before.capture.excludedApps, self.capture.excludedApps, capture.excludedApps)
        capture.excludedMenus = SettingsDraftMerge.set(before.capture.excludedMenus, self.capture.excludedMenus, capture.excludedMenus)
        return Self(showsAppSettings: SettingsDraftMerge.field(before.showsAppSettings, showsAppSettings, latest.showsAppSettings),
                    capture: capture,
                    history: .init(recentDays: SettingsDraftMerge.field(before.history.recentDays, history.recentDays, latest.history.recentDays),
                                   frequentDays: SettingsDraftMerge.field(before.history.frequentDays, history.frequentDays, latest.history.frequentDays)),
                    commands: SettingsDraftMerge.commands(before: before.commands, edited: commands, latest: latest.commands, tombstones: tombstones))
    }
    private struct EditableMenu: Equatable {
        let id: UUID
        let pinned: Bool
        let symbol: String?
        let shortcut: MenuShortcut?
        let axIdentifier: String?
        let optionAction: MenuActionReference?
        let icon: MenuResourceIcon?
        let binding: MenuResourceBinding?
        let identityVersion: Int?
        let aliases: [[String]]?
        init(_ command: MenuCommand) {
            id = command.id; pinned = command.isPinned; symbol = command.symbol; shortcut = command.shortcut
            axIdentifier = command.axIdentifier
            optionAction = command.optionAction
            icon = command.resourceIcon; binding = command.resourceBinding
            identityVersion = command.resourceIdentityVersion; aliases = command.pathAliases
        }
    }
}

public enum SettingsDraftConflict: Error, Equatable { case profile(String) }

public struct RegisteredSettingsDraft: Equatable {
    public var profiles: [LauncherProfile]
    public var selectedID: String
    public var followsFocus: Bool
    public init(profiles: [LauncherProfile], selectedID: String, followsFocus: Bool) {
        self.profiles = profiles; self.selectedID = selectedID; self.followsFocus = followsFocus
    }
    public func rebased(from before: Self, onto latest: Self) throws -> Self {
        let old = Dictionary(before.profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let editedIDs = Set(profiles.map(\.id))
        var result = latest.profiles
        for base in before.profiles where !editedIDs.contains(base.id) {
            if let current = result.first(where: { $0.id == base.id }), current != base {
                throw SettingsDraftConflict.profile(base.name)
            }
            result.removeAll { $0.id == base.id }
        }
        for edited in profiles {
            guard let base = old[edited.id] else {
                guard !result.contains(where: { $0.id == edited.id }) else { throw SettingsDraftConflict.profile(edited.name) }
                result.append(edited); continue
            }
            guard let index = result.firstIndex(where: { $0.id == edited.id }) else {
                if edited != base { throw SettingsDraftConflict.profile(edited.name) }
                continue
            }
            let current = result[index]
            if edited.items != base.items && current.items != base.items && current.items != edited.items {
                throw SettingsDraftConflict.profile(edited.name)
            }
            if edited.name != base.name && current.name != base.name && current.name != edited.name {
                throw SettingsDraftConflict.profile(edited.name)
            }
            result[index].name = SettingsDraftMerge.field(base.name, edited.name, current.name)
            result[index].items = SettingsDraftMerge.field(base.items, edited.items, current.items)
        }
        let ids = SettingsDraftMerge.order(before.profiles.map(\.id), profiles.map(\.id), result.map(\.id))
        let values = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = ids.compactMap { values[$0] }
        let selected = SettingsDraftMerge.field(before.selectedID, selectedID, latest.selectedID)
        guard !merged.isEmpty, merged.contains(where: { $0.id == selected }) else {
            throw SettingsDraftConflict.profile(profiles.first(where: { $0.id == selected })?.name ?? "선택한 프로필")
        }
        return Self(profiles: merged, selectedID: selected,
                    followsFocus: SettingsDraftMerge.field(before.followsFocus, followsFocus, latest.followsFocus))
    }
}
