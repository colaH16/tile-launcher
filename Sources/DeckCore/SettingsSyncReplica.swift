import Foundation

/// A CloudKit payload is one independently versioned record. An invalid record
/// must not prevent other menus/preferences from being imported.
public struct SettingsSyncRecord: Codable, Equatable {
    public var version = 1
    public var menu: SettingsSyncMenu?
    public var preference: String?
    public var value: SettingsSyncField<SettingsSyncValue>?
    public var appOrder: String?
    public var order: SettingsSyncField<[String]>?
    public init(menu: SettingsSyncMenu) { self.menu = menu }
    public init(preference: String, value: SettingsSyncField<SettingsSyncValue>) {
        self.preference = preference; self.value = value
    }
    public init(appOrder: String, order: SettingsSyncField<[String]>) { self.appOrder = appOrder; self.order = order }
    public var name: String {
        if let menu { return "menu-" + menu.id }
        if let preference { return "pref-" + preference }
        return "order-" + Data((appOrder ?? "").utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }
    public func fragment() throws -> SettingsSyncSnapshot {
        guard version == 1 else { throw SettingsSyncSnapshot.MergeError.unsupportedSchema }
        var result = SettingsSyncSnapshot()
        let branches = (menu == nil ? 0 : 1) + (preference == nil ? 0 : 1) + (appOrder == nil ? 0 : 1)
        guard branches == 1 else { throw SettingsSyncSnapshot.MergeError.inconsistentIdentity }
        if let menu { result.menus[menu.id] = menu }
        else if let preference, let value { result.preferences[preference] = value }
        else if let appOrder, !appOrder.isEmpty, let order { result.orders[appOrder] = order }
        else { throw SettingsSyncSnapshot.MergeError.inconsistentIdentity }
        try result.validate()
        return result
    }
}

public extension SettingsSyncSnapshot {
    var records: [SettingsSyncRecord] {
        menus.values.map(SettingsSyncRecord.init(menu:))
        + preferences.map { .init(preference: $0.key, value: $0.value) }
        + orders.map { .init(appOrder: $0.key, order: $0.value) }
    }
    mutating func merge(record: SettingsSyncRecord) throws {
        self = try merged(with: record.fragment())
    }
    /// Two Macs may have created the same command before meeting each other.
    /// Keep every original shared record and combine only verified identity or
    /// a unique exact full path in the same app. Never match a leaf title.
    var menuGroups: [[SettingsSyncMenu]] {
        var groups: [[SettingsSyncMenu]] = []
        for menu in menus.values.sorted(by: { $0.id < $1.id }) {
            let ids = Set((menu.aliases ?? []) + [menu.id])
            let matches = groups.indices.filter { index in
                groups[index].contains { !ids.isDisjoint(with: Set(($0.aliases ?? []) + [$0.id])) }
            }
            var group = [menu]
            for index in matches.reversed() { group += groups.remove(at: index) }
            groups.append(group.sorted { $0.id < $1.id })
        }
        return groups.sorted { $0[0].id < $1[0].id }
    }
    /// Called after a complete fetch, when uniqueness can be checked against
    /// all peers. Explicit aliases keep the decision stable on later fetches.
    mutating func reconcileMenuIdentities() throws {
        let groups = menuGroups
        func compatible(_ a: [SettingsSyncMenu], _ b: [SettingsSyncMenu]) -> Bool {
            var origins: [String: String] = [:]
            for menu in a + b {
                for (device, id) in menu.origins ?? [:] {
                    if let previous = origins[device], previous != id { return false }
                    origins[device] = id
                }
            }
            return a.allSatisfy { left in b.allSatisfy { right in
                guard left.appID == right.appID else { return false }
                if let x = left.resourceIdentity, let y = right.resourceIdentity { return x == y }
                return left.path == right.path
            } }
        }
        var candidates: [Int: [Int]] = [:]
        for i in groups.indices {
            candidates[i] = groups.indices.filter { i != $0 && compatible(groups[i], groups[$0]) }
        }
        for i in groups.indices {
            guard let peers = candidates[i], peers.count == 1, let j = peers.first,
                  i < j, candidates[j] == [i] else { continue }
            let all = (groups[i] + groups[j]).sorted { $0.id < $1.id }
            guard var merged = all.first else { continue }
            for other in all.dropFirst() {
                merged = try merged.merged(with: other.withID(merged.id))
            }
            merged.aliases = Array(Set(all.flatMap { ($0.aliases ?? []) + [$0.id] })).sorted()
            menus[merged.id] = merged
        }
    }
    var combinedMenus: [SettingsSyncMenu] {
        menuGroups.compactMap { group in
            guard var result = group.first else { return nil }
            for menu in group.dropFirst() {
                let sameID = SettingsSyncMenu(id: result.id, appID: menu.appID, appName: menu.appName,
                    path: menu.path, resourceIdentity: menu.resourceIdentity, presence: menu.presence,
                    pinned: menu.pinned, icon: menu.icon, aliases: menu.aliases, origins: menu.origins)
                guard let merged = try? result.merged(with: sameID) else { return nil }
                result = merged
            }
            return result
        }
    }
    var canonicalMenuIDs: [String: String] {
        var result: [String: String] = [:]
        for group in menuGroups {
            guard let canonical = group.first?.id else { continue }
            for menu in group { result[menu.id] = canonical }
        }
        return result
    }
}

/// Editable local values only. Runtime counters, menu shortcuts, acquired icon
/// caches, registered apps, profiles and collection preferences never leave here.
public struct SettingsSyncProjection: Codable, Equatable {
    public var preferences: [String: SettingsSyncValue]
    public var commands: [MenuCommand]
    public init(preferences: [String: SettingsSyncValue], commands: [MenuCommand]) {
        self.preferences = preferences; self.commands = commands
    }
}

public struct SettingsSyncReplica: Codable {
    public var device = UUID().uuidString
    public var sequence: UInt64 = 0
    public var snapshot = SettingsSyncSnapshot()
    /// Local command IDs stay independent of shared record IDs.
    public var localIDs: [UUID: String] = [:]
    public init() {}
    private mutating func stamp(at date: Date?) -> SettingsSyncStamp {
        if sequence == UInt64.max { device = UUID().uuidString; sequence = 0 }
        sequence += 1
        return .init(date: date, device: device, sequence: sequence)
    }
    public mutating func capture(before: SettingsSyncProjection?, after: SettingsSyncProjection,
                                 at date: Date, iconBases: [UUID: [String: UInt64]] = [:]) {
        let oldPreferences = before?.preferences ?? [:]
        for (key, value) in after.preferences where snapshot.preferences[key] == nil || oldPreferences[key] != value {
            guard let keyType = SettingsSyncPreference(rawValue: key), keyType.accepts(value) else { continue }
            let initial = before == nil && snapshot.preferences[key] == nil
            snapshot.preferences[key] = .init(value, stamp: stamp(at: initial ? nil : date))
        }
        let oldCommands = Dictionary((before?.commands ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingIDs = Set(after.commands.map(\.id))
        let canonical = snapshot.canonicalMenuIDs
        var appIDs = Set<String>()
        for command in after.commands {
            guard !command.appID.hasPrefix("/"),
                  !command.isAutomatic || command.isPinned || command.symbol != nil || localIDs[command.id] != nil else { continue }
            let mapped = localIDs[command.id].flatMap { canonical[$0] ?? $0 }
            let group = snapshot.combinedMenus.filter { menu in
                guard menu.appID == command.appID else { return false }
                if let local = menu.origins?[device], local != command.id.uuidString, menu.isPresent { return false }
                if let a = menu.resourceIdentity, let b = command.resourceBinding?.identity { return a == b }
                return menu.path == command.path
            }
            let syncID = mapped ?? (group.count == 1 ? group[0].id : UUID().uuidString)
            localIDs[command.id] = syncID
            appIDs.insert(command.appID)
            var record = snapshot.combinedMenus.first { $0.id == syncID }
            let old = oldCommands[command.id]
            if record == nil {
                let time = stamp(at: before == nil ? nil : date)
                record = .init(id: syncID, appID: command.appID, appName: command.appName, path: command.path,
                    resourceIdentity: command.resourceBinding?.identity, presence: .init(true, stamp: time),
                    pinned: .init(command.isPinned, stamp: time),
                    icon: .init([.init(symbol: command.symbol, stamp: time)]), origins: [device: command.id.uuidString])
            } else if old == nil, before != nil {
                if !command.isAutomatic { record!.presence = .init(true, stamp: stamp(at: date)) }
                if record!.pinned.value != command.isPinned { record!.pinned = .init(command.isPinned, stamp: stamp(at: date)) }
                if record!.icon.displayed != command.symbol {
                    let observed = iconBases[command.id] ?? record!.icon.observed
                    record!.icon = record!.icon.merged(with: .init([.init(symbol: command.symbol, stamp: stamp(at: date), observed: observed)]))
                }
            } else if let old {
                if old.isPinned != command.isPinned { record!.pinned = .init(command.isPinned, stamp: stamp(at: date)) }
                if old.symbol != command.symbol {
                    let observed = iconBases[command.id] ?? record!.icon.observed
                    let edit = SettingsSyncIconEdit(symbol: command.symbol, stamp: stamp(at: date), observed: observed)
                    record!.icon = record!.icon.merged(with: .init([edit]))
                }
            }
            if let record { snapshot.menus[syncID] = record }
        }
        for command in before?.commands ?? [] where !existingIDs.contains(command.id) {
            guard let shared = localIDs[command.id] else { continue }
            let id = canonical[shared] ?? shared
            guard var menu = snapshot.combinedMenus.first(where: { $0.id == id }) else { continue }
            menu.presence = .init(false, stamp: stamp(at: date)); snapshot.menus[id] = menu
            appIDs.insert(menu.appID)
        }
        for appID in appIDs {
            let current = after.commands.filter { $0.appID == appID }.compactMap { localIDs[$0.id] }
            let old = (before?.commands ?? []).filter { $0.appID == appID }.compactMap { localIDs[$0.id] }
            let previous = snapshot.orders[appID]?.value ?? []
            let shared = Set(current).intersection(old)
            let reordered = current.filter(shared.contains) != old.filter(shared.contains)
            let added = current.filter { !previous.contains($0) }
            if snapshot.orders[appID] == nil || reordered || !added.isEmpty {
                var order = previous
                if reordered {
                    var desired = current.filter(Set(previous).contains).makeIterator()
                    let present = Set(current)
                    order = previous.map { present.contains($0) ? (desired.next() ?? $0) : $0 }
                }
                order += added
                snapshot.orders[appID] = .init(order, stamp: stamp(at: before == nil ? nil : date))
            }
        }
    }
    public mutating func applying(to projection: SettingsSyncProjection) -> SettingsSyncProjection {
        var result = projection
        for (key, field) in snapshot.preferences { result.preferences[key] = field.value }
        let canonical = snapshot.canonicalMenuIDs
        for (local, shared) in localIDs { localIDs[local] = canonical[shared] ?? shared }
        let groups = snapshot.combinedMenus
        for menu in groups {
            let matches = result.commands.indices.filter { index in
                let command = result.commands[index]
                if localIDs[command.id] == menu.id { return true }
                guard command.appID == menu.appID else { return false }
                if let a = menu.resourceIdentity, let b = command.resourceBinding?.identity { return a == b }
                return command.path == menu.path
            }
            guard matches.count <= 1 else { continue } // ambiguous identity remains untouched
            if !menu.isPresent {
                if let index = matches.first { localIDs[result.commands[index].id] = menu.id; result.commands.remove(at: index) }
                continue
            }
            if let index = matches.first {
                localIDs[result.commands[index].id] = menu.id
                result.commands[index].isPinned = menu.pinned.value
                result.commands[index].symbol = menu.icon.displayed
                result.commands[index].syncResourceIdentity = menu.resourceIdentity
            } else {
                var command = MenuCommand(appID: menu.appID, appName: menu.appName, path: menu.path, isPinned: menu.pinned.value)
                // Shared resource hints are not execution bindings on this Mac.
                if let local = localIDs.first(where: { $0.value == menu.id })?.key { command.id = local }
                command.symbol = menu.icon.displayed; command.syncResourceIdentity = menu.resourceIdentity
                localIDs[command.id] = menu.id; result.commands.append(command)
            }
        }
        for appID in Set(groups.map(\.appID)) {
            var seen = Set<String>()
            let ordered = (snapshot.orders[appID]?.value ?? []).map { canonical[$0] ?? $0 }.filter { seen.insert($0).inserted }
            let ranks = Dictionary(ordered.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
            let indices = result.commands.indices.filter { result.commands[$0].appID == appID && localIDs[result.commands[$0].id] != nil }
            let sorted = indices.map { result.commands[$0] }.enumerated().sorted {
                let a = ranks[localIDs[$0.element.id] ?? ""] ?? Int.max
                let b = ranks[localIDs[$1.element.id] ?? ""] ?? Int.max
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            for (index, value) in zip(indices, sorted) { result.commands[index] = value }
        }
        return result
    }
    public mutating func chooseIcon(menuID: String, symbol: String?, at date: Date) {
        guard var menu = snapshot.combinedMenus.first(where: { $0.id == menuID }) else { return }
        let combined = menu.icon
        menu.icon = combined.choosing(symbol, stamp: stamp(at: date))
        snapshot.menus[menuID] = menu
    }
}

private extension SettingsSyncMenu {
    func withID(_ id: String) -> Self {
        .init(id: id, appID: appID, appName: appName, path: path, resourceIdentity: resourceIdentity,
              presence: presence, pinned: pinned, icon: icon, aliases: aliases, origins: origins)
    }
}

public extension SettingsSyncReplica {
    func legacyConflicts(with remote: SettingsSyncSnapshot) -> [String] {
        var result: [String] = []
        var common = (try? snapshot.merged(with: remote)) ?? snapshot
        try? common.reconcileMenuIdentities()
        let ids = common.canonicalMenuIDs
        for (key, own) in snapshot.preferences {
            if let other = remote.preferences[key], own.stamp.date == nil, other.stamp.date == nil, own.value != other.value {
                result.append("pref:" + key)
            }
        }
        for (key, own) in snapshot.orders {
            if let other = remote.orders[key], own.stamp.date == nil, other.stamp.date == nil {
                let a = own.value.map { ids[$0] ?? $0 }, b = other.value.map { ids[$0] ?? $0 }
                let shared = Set(a).intersection(b)
                if a.filter(shared.contains) != b.filter(shared.contains) { result.append("order:" + key) }
            }
        }
        for own in snapshot.combinedMenus {
            let matches = remote.combinedMenus.filter { other in
                guard own.appID == other.appID else { return false }
                if own.id == other.id { return true }
                if let a = own.resourceIdentity, let b = other.resourceIdentity { return a == b }
                return own.path == other.path
            }
            if matches.count == 1, let other = matches.first,
               own.pinned.stamp.date == nil, other.pinned.stamp.date == nil, own.pinned.value != other.pinned.value {
                result.append("pin:" + own.id)
            }
        }
        return result.sorted()
    }
    mutating func mergeInitial(_ remote: SettingsSyncSnapshot, preferLocal: Bool?, at date: Date) throws {
        let old = snapshot
        let conflicts = legacyConflicts(with: remote)
        snapshot = try old.merged(with: remote)
        try snapshot.reconcileMenuIdentities()
        guard let preferLocal else { return }
        for key in legacyKeys(old.preferences, remote.preferences) {
            let field = preferLocal ? old.preferences[key]! : remote.preferences[key]!
            snapshot.preferences[key] = .init(field.value, stamp: stamp(at: date))
        }
        for key in conflicts.filter({ $0.hasPrefix("order:") }).map({ String($0.dropFirst(6)) }) {
            let field = preferLocal ? old.orders[key]! : remote.orders[key]!
            snapshot.orders[key] = .init(field.value, stamp: stamp(at: date))
        }
        let ids = snapshot.canonicalMenuIDs
        for local in old.combinedMenus {
            let id = ids[local.id] ?? local.id
            let matches = remote.combinedMenus.filter { (ids[$0.id] ?? $0.id) == id }
            guard matches.count == 1, let cloud = matches.first,
                  local.pinned.stamp.date == nil, cloud.pinned.stamp.date == nil,
                  local.pinned.value != cloud.pinned.value,
                  var menu = snapshot.combinedMenus.first(where: { $0.id == id }) else { continue }
            menu.pinned = .init(preferLocal ? local.pinned.value : cloud.pinned.value, stamp: stamp(at: date))
            snapshot.menus[id] = menu
        }
    }
    private func legacyKeys<T>(_ own: [String: SettingsSyncField<T>], _ remote: [String: SettingsSyncField<T>]) -> [String] {
        own.keys.filter { key in
            guard let a = own[key], let b = remote[key] else { return false }
            return a.stamp.date == nil && b.stamp.date == nil && a.value != b.value
        }
    }
}
