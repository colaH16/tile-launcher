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
        if let menu, value == nil, order == nil { result.menus[menu.id] = menu }
        else if let preference, let value, order == nil { result.preferences[preference] = value }
        else if let appOrder, !appOrder.isEmpty, let order, value == nil { result.orders[appOrder] = order }
        else { throw SettingsSyncSnapshot.MergeError.inconsistentIdentity }
        try result.validate()
        return result
    }
    /// A record from another Mac. Re-encoding drops keys this version does not
    /// know, so a payload with unknown keys is rejected (and kept quarantined)
    /// instead of being decoded and later overwritten without them.
    public static func decodeVerified(_ data: Data) throws -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data), PayloadSchema.record(root) else {
            throw SettingsSyncSnapshot.MergeError.unsupportedSchema
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

private enum PayloadSchema {
    static func only(_ value: Any, _ keys: Set<String>) -> [String: Any]? {
        guard let object = value as? [String: Any], Set(object.keys).isSubset(of: keys) else { return nil }
        return object
    }
    static func record(_ value: Any) -> Bool {
        guard let object = only(value, ["version", "menu", "preference", "value", "appOrder", "order"]) else { return false }
        if let menu = object["menu"], !self.menu(menu) { return false }
        if let field = object["value"], !self.field(field, inner: { setting($0) }) { return false }
        if let field = object["order"], !self.field(field, inner: { $0 is [Any] }) { return false }
        return true
    }
    static func field(_ value: Any, inner: (Any) -> Bool) -> Bool {
        guard let object = only(value, ["value", "stamp"]) else { return false }
        return (object["value"].map(inner) ?? true) && (object["stamp"].map(stamp) ?? true)
    }
    static func stamp(_ value: Any) -> Bool { only(value, ["date", "device", "sequence"]) != nil }
    static func setting(_ value: Any) -> Bool {
        guard let object = only(value, ["bool", "integer", "seconds", "text", "color"]) else { return false }
        return object.values.allSatisfy { only($0, ["_0"]) != nil }
    }
    static func menu(_ value: Any) -> Bool {
        guard let object = only(value, ["id", "appID", "appName", "path", "resourceIdentity", "presence",
                                        "pinned", "icon", "aliases", "origins", "executionIdentifier"]) else { return false }
        if let identity = object["resourceIdentity"], only(identity, ["appID", "archive", "keys"]) == nil { return false }
        for key in ["presence", "pinned"] {
            if let value = object[key], !field(value, inner: { _ in true }) { return false }
        }
        if let value = object["executionIdentifier"], !field(value, inner: { $0 is NSNull || $0 is String }) { return false }
        if let icon = object["icon"] {
            guard let edits = only(icon, ["edits"])?["edits"] as? [Any] else { return false }
            for edit in edits {
                guard let edit = only(edit, ["symbol", "stamp", "observed"]) else { return false }
                if let value = edit["stamp"], !stamp(value) { return false }
            }
        }
        return true
    }
}

private struct SettingsSyncPathKey: Hashable {
    let appID: String
    let path: [String]
}

public extension SettingsSyncSnapshot {
    var records: [SettingsSyncRecord] {
        menus.values.map(SettingsSyncRecord.init(menu:))
        + preferences.map { .init(preference: $0.key, value: $0.value) }
        + orders.map { .init(appOrder: $0.key, order: $0.value) }
    }
    /// Look up one raw record without rebuilding the complete outgoing map.
    func record(named name: String) -> SettingsSyncRecord? {
        if name.hasPrefix("menu-"), let menu = menus[String(name.dropFirst(5))] {
            return .init(menu: menu)
        }
        if name.hasPrefix("pref-") {
            let key = String(name.dropFirst(5))
            if let field = preferences[key] { return .init(preference: key, value: field) }
        }
        if name.hasPrefix("order-") {
            let encoded = String(name.dropFirst(6)).replacingOccurrences(of: "_", with: "/")
                .replacingOccurrences(of: "-", with: "+")
            if let data = Data(base64Encoded: encoded), let key = String(data: data, encoding: .utf8),
               let field = orders[key] {
                let record = SettingsSyncRecord(appOrder: key, order: field)
                return record.name == name ? record : nil
            }
        }
        return nil
    }
    mutating func merge(record: SettingsSyncRecord) throws {
        guard schema == Self.currentSchema else { throw MergeError.unsupportedSchema }
        let fragment = try record.fragment()
        // Validate the incoming and affected local record before mutation.
        // Full snapshots are validated on load/bulk merge; copying/scanning all
        // other records for every fetched item makes a batch quadratic.
        if let (key, value) = fragment.menus.first {
            if let own = menus[key] {
                _ = try SettingsSyncRecord(menu: own).fragment()
                menus[key] = try own.merged(with: value)
            } else { menus[key] = value }
        } else if let (key, value) = fragment.preferences.first {
            if let own = preferences[key] {
                _ = try SettingsSyncRecord(preference: key, value: own).fragment()
                preferences[key] = own.merged(with: value)
            } else { preferences[key] = value }
        } else if let (key, value) = fragment.orders.first {
            if let own = orders[key] {
                _ = try SettingsSyncRecord(appOrder: key, order: own).fragment()
                orders[key] = own.merged(with: value)
            } else { orders[key] = value }
        }
    }
    /// Two Macs may have created the same command before meeting each other.
    /// Keep every original shared record and combine only verified identity or
    /// a unique exact full path in the same app. Never match a leaf title.
    var menuGroups: [[SettingsSyncMenu]] {
        // Index aliases once rather than rebuilding/scanning every existing
        // group for each menu. Group IDs stay stable while groups are joined.
        var groups: [Int: [SettingsSyncMenu]] = [:]
        var owners: [String: Set<Int>] = [:]
        for (index, menu) in menus.values.sorted(by: { $0.id < $1.id }).enumerated() {
            let ids = Set((menu.aliases ?? []) + [menu.id])
            let matches = ids.reduce(into: Set<Int>()) { $0.formUnion(owners[$1] ?? []) }.sorted()
            let candidates = [menu] + matches.flatMap { groups[$0] ?? [] }
            var group = [menu]
            // Conflicting aliases must not chain distinct commands of one Mac.
            if Self.consistent(candidates) {
                for owner in matches {
                    for member in groups.removeValue(forKey: owner) ?? [] {
                        for alias in Set((member.aliases ?? []) + [member.id]) {
                            owners[alias]?.remove(owner)
                        }
                        group.append(member)
                    }
                }
            }
            groups[index] = group.sorted { $0.id < $1.id }
            for member in group {
                for alias in Set((member.aliases ?? []) + [member.id]) {
                    owners[alias, default: []].insert(index)
                }
            }
        }
        return groups.values.sorted { $0[0].id < $1[0].id }
    }
    static func consistent(_ menus: [SettingsSyncMenu]) -> Bool {
        guard Set(menus.map(\.appID)).count <= 1 else { return false }
        var origins: [String: String] = [:]
        for menu in menus {
            for (device, id) in menu.origins ?? [:] {
                if let previous = origins[device], previous != id { return false }
                origins[device] = id
            }
        }
        return true
    }
    /// Called after a complete fetch, when uniqueness can be checked against
    /// all peers. Explicit aliases keep the decision stable on later fetches.
    mutating func reconcileMenuIdentities() throws {
        let groups = menuGroups
        func compatible(_ a: [SettingsSyncMenu], _ b: [SettingsSyncMenu]) -> Bool {
            guard Self.consistent(a + b) else { return false }
            return a.allSatisfy { left in b.allSatisfy { right in
                guard left.appID == right.appID else { return false }
                if let x = left.resourceIdentity, let y = right.resourceIdentity { return x == y }
                return left.path == right.path
            } }
        }
        var paths: [SettingsSyncPathKey: Set<Int>] = [:]
        var resources: [MenuResourceIdentity: Set<Int>] = [:]
        for i in groups.indices {
            for menu in groups[i] {
                paths[.init(appID: menu.appID, path: menu.path), default: []].insert(i)
                if let identity = menu.resourceIdentity { resources[identity, default: []].insert(i) }
            }
        }
        var candidates: [Int: Set<Int>] = [:]
        for i in groups.indices {
            var possible = Set<Int>()
            for menu in groups[i] {
                possible.formUnion(paths[.init(appID: menu.appID, path: menu.path)] ?? [])
                if let identity = menu.resourceIdentity { possible.formUnion(resources[identity] ?? []) }
            }
            candidates[i] = Set(possible.filter { i != $0 && compatible(groups[i], groups[$0]) })
        }
        var joined = Set<Int>()
        for i in groups.indices where !joined.contains(i) {
            let peers = (candidates[i] ?? []).union([i])
            // Every peer must agree on exactly the same complete group. This
            // supports three or more Macs without accepting weak bridges or
            // ambiguous duplicates from any one Mac.
            guard peers.count > 1,
                  peers.allSatisfy({ candidates[$0] == peers.subtracting([$0]) }) else { continue }
            let all = peers.sorted().flatMap { groups[$0] }.sorted { $0.id < $1.id }
            guard Self.consistent(all) else { continue }
            guard var merged = all.first else { continue }
            for other in all.dropFirst() {
                merged = try merged.merged(with: other.withID(merged.id))
            }
            merged.aliases = Array(Set(all.flatMap { ($0.aliases ?? []) + [$0.id] })).sorted()
            menus[merged.id] = merged
            joined.formUnion(peers)
        }
    }
    var combinedMenus: [SettingsSyncMenu] {
        menuGroups.compactMap { group in
            guard var result = group.first else { return nil }
            for menu in group.dropFirst() {
                let sameID = SettingsSyncMenu(id: result.id, appID: menu.appID, appName: menu.appName,
                    path: menu.path, resourceIdentity: menu.resourceIdentity, presence: menu.presence,
                    pinned: menu.pinned, icon: menu.icon, aliases: menu.aliases, origins: menu.origins,
                    executionIdentifier: menu.executionIdentifier)
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
        // Menu execution and icon-resource cache updates save local defaults
        // frequently. They cannot change the shared editable values, so do not
        // rebuild identity groups or serialize a journal for those events.
        if let before, before.preferences == after.preferences,
           before.commands.count == after.commands.count,
           zip(before.commands, after.commands).allSatisfy({ a, b in
               a.id == b.id && a.appID == b.appID && a.isAutomatic == b.isAutomatic
                   && a.isPinned == b.isPinned && a.symbol == b.symbol
           }) { return }
        let oldPreferences = before?.preferences ?? [:]
        for (key, value) in after.preferences {
            guard let keyType = SettingsSyncPreference(rawValue: key), keyType.accepts(value) else { continue }
            // Only a change from the previously observed value is a user edit;
            // a newly tracked key keeps an unknown (legacy) time.
            let edited = oldPreferences[key].map { $0 != value } ?? false
            guard edited || snapshot.preferences[key] == nil else { continue }
            snapshot.preferences[key] = .init(value, stamp: stamp(at: edited ? date : nil))
        }
        let oldCommands = Dictionary((before?.commands ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingIDs = Set(after.commands.map(\.id))
        let canonical = snapshot.canonicalMenuIDs
        var combined = Dictionary(snapshot.combinedMenus.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // One shared record belongs to at most one local command on this Mac.
        var claimed: [String: UUID] = [:]
        for command in after.commands {
            if let shared = localIDs[command.id] { claimed[canonical[shared] ?? shared] = command.id }
        }
        var touchedApps = Set<String>()
        for command in after.commands {
            guard !command.appID.hasPrefix("/"),
                  !command.isAutomatic || command.isPinned || command.symbol != nil || localIDs[command.id] != nil else { continue }
            let syncID: String
            if let mapped = localIDs[command.id] { syncID = canonical[mapped] ?? mapped }
            else {
                let group = combined.values.filter { menu in
                    guard menu.appID == command.appID, claimed[menu.id] == nil else { return false }
                    if let local = menu.origins?[device], local != command.id.uuidString, menu.isPresent { return false }
                    if let a = menu.resourceIdentity, let b = command.resourceBinding?.identity { return a == b }
                    return menu.path == command.path
                }
                syncID = group.count == 1 ? group[0].id : UUID().uuidString
            }
            localIDs[command.id] = syncID; claimed[syncID] = command.id
            var record = combined[syncID]
            let old = oldCommands[command.id]
            if old == nil && before != nil { touchedApps.insert(command.appID) }
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
            if var record {
                // Adopting a remote record must also establish this Mac's
                // distinct identity before any later alias reconciliation.
                // Keep the original origin on re-addition: replacing it would
                // conflict with already-synced copies of the same record.
                if record.origins?[device] == nil {
                    var origins = record.origins ?? [:]
                    origins[device] = command.id.uuidString
                    record.origins = origins
                }
                snapshot.menus[syncID] = record; combined[syncID] = record
            }
        }
        for command in before?.commands ?? [] where !existingIDs.contains(command.id) {
            guard let shared = localIDs[command.id] else { continue }
            let id = canonical[shared] ?? shared
            guard var menu = combined[id] else { continue }
            menu.presence = .init(false, stamp: stamp(at: date)); snapshot.menus[id] = menu; combined[id] = menu
            touchedApps.insert(menu.appID)
        }
        let managed = after.commands.filter { localIDs[$0.id] != nil }
        for appID in Set(managed.map(\.appID)).union(touchedApps) {
            let current = after.commands.filter { $0.appID == appID }.compactMap { localIDs[$0.id] }
            let old = (before?.commands ?? []).filter { $0.appID == appID }.compactMap { localIDs[$0.id] }
            var seen = Set<String>()
            let previous = (snapshot.orders[appID]?.value ?? []).map { canonical[$0] ?? $0 }.filter { seen.insert($0).inserted }
            guard before != nil else {
                if snapshot.orders[appID] == nil { snapshot.orders[appID] = .init(current, stamp: stamp(at: nil)) }
                continue
            }
            let shared = Set(current).intersection(old)
            let reordered = current.filter(shared.contains) != old.filter(shared.contains)
            // Only a command added by this edit claims a new slot. Remote menus
            // missing from the list are ordered on apply without a new stamp.
            let oldIDs = Set(old)
            let added = current.filter { !oldIDs.contains($0) && !seen.contains($0) }
            guard reordered || !added.isEmpty else { continue }
            let present = Set(current)
            var desired = current.makeIterator()
            var order = previous.map { present.contains($0) ? (desired.next() ?? $0) : $0 }
            while let next = desired.next() { order.append(next) }
            snapshot.orders[appID] = .init(order, stamp: stamp(at: date))
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
                // A command linked to another shared record is never re-linked
                // by path, and a deletion only removes the command linked to it.
                if let linked = localIDs[command.id] { return linked == menu.id }
                guard menu.isPresent, command.appID == menu.appID else { return false }
                if let a = menu.resourceIdentity, let b = command.resourceBinding?.identity { return a == b }
                return command.path == menu.path
            }
            guard matches.count <= 1 else { continue } // ambiguous identity remains untouched
            if !menu.isPresent {
                if let index = matches.first { result.commands.remove(at: index) }
                continue
            }
            if let index = matches.first {
                localIDs[result.commands[index].id] = menu.id
                result.commands[index].isPinned = menu.pinned.value
                result.commands[index].symbol = menu.icon.displayed
                // A command that already ran on this Mac keeps its own binding;
                // only a menu first created from iCloud waits for verification.
                if result.commands[index].syncResourceIdentity != nil {
                    result.commands[index].syncResourceIdentity = menu.resourceIdentity
                }
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
              presence: presence, pinned: pinned, icon: icon, aliases: aliases, origins: origins,
              executionIdentifier: executionIdentifier)
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
        // Same pairing as mergeInitial: only menus the reconciliation joined.
        for own in snapshot.combinedMenus {
            let id = ids[own.id] ?? own.id
            let matches = remote.combinedMenus.filter { (ids[$0.id] ?? $0.id) == id }
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
