import Foundation

/// Real user edit time, never adjusted to a remote device's wall clock.
/// A nil date is an imported legacy value, not an invented edit.
public struct SettingsSyncStamp: Codable, Equatable, Comparable {
    public let date: Date?
    public let device: String
    public let sequence: UInt64
    public init(date: Date?, device: String, sequence: UInt64) {
        self.date = date; self.device = device; self.sequence = sequence
    }
    var isValid: Bool {
        !device.isEmpty && sequence > 0 && (date?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }
    public static func < (a: Self, b: Self) -> Bool {
        if a.date == nil && b.date != nil { return true }
        if a.date != nil && b.date == nil { return false }
        if let ad = a.date, let bd = b.date, ad != bd { return ad < bd }
        if a.device != b.device { return a.device < b.device }
        return a.sequence < b.sequence
    }
}

public struct SettingsSyncField<Value: Codable & Equatable>: Codable, Equatable {
    public var value: Value
    public var stamp: SettingsSyncStamp
    public init(_ value: Value, stamp: SettingsSyncStamp) { self.value = value; self.stamp = stamp }
    public func merged(with other: Self) -> Self {
        if stamp != other.stamp { return stamp < other.stamp ? other : self }
        return SettingsSyncCoding.key(value).lexicographicallyPrecedes(SettingsSyncCoding.key(other.value)) ? other : self
    }
}

/// Causal metadata is separate from wall time: delayed uploads alone must not
/// turn a sequential icon edit into a conflict or hide an independent edit.
public struct SettingsSyncIconEdit: Codable, Equatable {
    public let symbol: String? // nil = default; hidden sentinel is an ordinary choice.
    public let stamp: SettingsSyncStamp
    public let observed: [String: UInt64]
    public init(symbol: String?, stamp: SettingsSyncStamp, observed: [String: UInt64] = [:]) {
        self.symbol = symbol; self.stamp = stamp; self.observed = observed
    }
    public var id: String { "\(stamp.device):\(stamp.sequence)" }
    public func follows(_ other: Self) -> Bool {
        (observed[other.stamp.device] ?? 0) >= other.stamp.sequence
    }
}

public struct SettingsSyncIcon: Codable, Equatable {
    public private(set) var edits: [SettingsSyncIconEdit]
    public init(_ edits: [SettingsSyncIconEdit]) { self.edits = Self.normalized(edits) }
    private enum CodingKeys: String, CodingKey { case edits }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([SettingsSyncIconEdit].self, forKey: .edits)
        for edit in values {
            guard edit.stamp.isValid,
                  (edit.observed[edit.stamp.device] ?? 0) < edit.stamp.sequence else {
                throw DecodingError.dataCorruptedError(forKey: .edits, in: container, debugDescription: "Invalid icon edit identity")
            }
        }
        self.init(values)
    }
    public var needsChoice: Bool { Set(edits.map { $0.symbol }).count > 1 }
    public var displayed: String? { edits.max { $0.stamp < $1.stamp }?.symbol }
    public var observed: [String: UInt64] {
        var result: [String: UInt64] = [:]
        for edit in edits {
            for (device, count) in edit.observed { result[device] = max(result[device] ?? 0, count) }
            result[edit.stamp.device] = max(result[edit.stamp.device] ?? 0, edit.stamp.sequence)
        }
        return result
    }
    public func merged(with other: Self) -> Self { Self(edits + other.edits) }
    public func choosing(_ symbol: String?, stamp: SettingsSyncStamp) -> Self {
        Self([.init(symbol: symbol, stamp: stamp, observed: observed)])
    }
    private static func normalized(_ values: [SettingsSyncIconEdit]) -> [SettingsSyncIconEdit] {
        let unique = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            SettingsSyncCoding.key(a).lexicographicallyPrecedes(SettingsSyncCoding.key(b)) ? b : a
        })
        let all = Array(unique.values)
        return all.filter { candidate in
            !all.contains { $0.id != candidate.id && $0.follows(candidate) }
        }.sorted { $0.id < $1.id }
    }
}

public struct SettingsSyncMenu: Codable, Equatable, Identifiable {
    public let id: String
    public let appID: String
    public var appName: String
    public var path: [String]
    /// Resource identity is a matching hint, validated against the receiving app.
    public var resourceIdentity: MenuResourceIdentity?
    public var presence: SettingsSyncField<Bool>
    public var pinned: SettingsSyncField<Bool>
    public var icon: SettingsSyncIcon
    public var aliases: [String]?
    public var origins: [String: String]?
    public var lastEdit: SettingsSyncStamp {
        (icon.edits.map(\.stamp) + [presence.stamp, pinned.stamp]).max()!
    }
    public init(id: String, appID: String, appName: String, path: [String],
                resourceIdentity: MenuResourceIdentity? = nil, presence: SettingsSyncField<Bool>,
                pinned: SettingsSyncField<Bool>, icon: SettingsSyncIcon, aliases: [String]? = nil, origins: [String: String]? = nil) {
        self.id = id; self.appID = appID; self.appName = appName; self.path = path
        self.resourceIdentity = resourceIdentity; self.presence = presence; self.pinned = pinned
        self.icon = icon; self.aliases = aliases; self.origins = origins
    }
    public var isPresent: Bool {
        presence.value || (lastEdit.date != nil && presence.stamp < lastEdit)
    }
    public func merged(with other: Self) throws -> Self {
        guard id == other.id && appID == other.appID else { throw SettingsSyncSnapshot.MergeError.inconsistentIdentity }
        let ownMetadata = [resourceIdentity == nil ? "0" : "1", appName,
                           SettingsSyncCoding.string(path), SettingsSyncCoding.string(resourceIdentity)]
        let remoteMetadata = [other.resourceIdentity == nil ? "0" : "1", other.appName,
                              SettingsSyncCoding.string(other.path), SettingsSyncCoding.string(other.resourceIdentity)]
        var value = ownMetadata.lexicographicallyPrecedes(remoteMetadata) ? other : self
        value.presence = presence.merged(with: other.presence)
        value.pinned = pinned.merged(with: other.pinned)
        value.icon = icon.merged(with: other.icon)
        value.aliases = aliases == nil && other.aliases == nil ? nil : Array(Set((aliases ?? [id]) + (other.aliases ?? [id]))).sorted()
        var origins = self.origins ?? [:]
        for (device, localID) in other.origins ?? [:] {
            if let own = origins[device], own != localID { throw SettingsSyncSnapshot.MergeError.inconsistentIdentity }
            origins[device] = localID
        }
        value.origins = origins.isEmpty ? nil : origins
        return value
    }
}

public enum SettingsSyncValue: Codable, Equatable {
    case bool(Bool), integer(Int), seconds(Double), text(String), color(UInt32?)
}

/// Only these preferences are eligible; local collection, history, profiles,
/// permissions and login items can never enter a snapshot by accident.
public enum SettingsSyncPreference: String, Codable, CaseIterable {
    case reopenEnabled, reopenInterval, numberShortcuts, automaticWindowCount, manualWindowCount
    case theme, menuColor, windowColor, handoffColor, registeredColor, showAppSettings
}

public struct SettingsSyncSnapshot: Codable, Equatable {
    public static let currentSchema = 1
    public var schema = currentSchema
    public var preferences: [String: SettingsSyncField<SettingsSyncValue>] = [:]
    public var menus: [String: SettingsSyncMenu] = [:]
    /// Includes unpinned/deleted managed menus to preserve position on re-pin.
    public var orders: [String: SettingsSyncField<[String]>] = [:]
    public init() {}
    public enum MergeError: Error { case unsupportedSchema, inconsistentIdentity, invalidPreference }
    public func merged(with remote: Self) throws -> Self {
        guard schema == Self.currentSchema && remote.schema == Self.currentSchema else { throw MergeError.unsupportedSchema }
        try validate(); try remote.validate()
        var result = self
        for (key, value) in remote.preferences {
            result.preferences[key] = preferences[key]?.merged(with: value) ?? value
        }
        for (key, value) in remote.menus {
            guard value.id == key else { throw MergeError.inconsistentIdentity }
            if let own = result.menus[key] {
                guard own.appID == value.appID else { throw MergeError.inconsistentIdentity }
                result.menus[key] = try own.merged(with: value)
            } else { result.menus[key] = value }
        }
        for (key, value) in remote.orders { result.orders[key] = orders[key]?.merged(with: value) ?? value }
        return result
    }
    public func validate() throws {
        guard schema == Self.currentSchema else { throw MergeError.unsupportedSchema }
        for (key, field) in preferences {
            guard let preference = SettingsSyncPreference(rawValue: key), preference.accepts(field.value), field.stamp.isValid else {
                throw MergeError.invalidPreference
            }
        }
        for (key, menu) in menus {
            guard key == menu.id && !key.isEmpty && !menu.appID.isEmpty && !menu.appID.hasPrefix("/"),
                  menu.path.count >= 2, menu.path.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  menu.presence.stamp.isValid, menu.pinned.stamp.isValid,
                  !menu.icon.edits.isEmpty, menu.icon.edits.allSatisfy({ $0.stamp.isValid }),
                  menu.aliases?.allSatisfy({ !$0.isEmpty }) ?? true,
                  menu.origins?.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty }) ?? true else {
                throw MergeError.inconsistentIdentity
            }
            if let identity = menu.resourceIdentity {
                guard identity.appID == menu.appID, !identity.archive.isEmpty,
                      !identity.keys.isEmpty, identity.keys.allSatisfy({ !$0.isEmpty }) else { throw MergeError.inconsistentIdentity }
            }
        }
        for (appID, field) in orders {
            guard !appID.isEmpty, !appID.hasPrefix("/"), field.stamp.isValid,
                  field.value.allSatisfy({ !$0.isEmpty }), Set(field.value).count == field.value.count else {
                throw MergeError.inconsistentIdentity
            }
        }
    }
    public func orderedIDs(appID: String, includingDeleted: Bool = false) -> [String] {
        let eligible = Set(menus.values.filter { $0.appID == appID && (includingDeleted || $0.isPresent) }.map(\.id))
        var seen = Set<String>()
        let chosen = (orders[appID]?.value ?? []).filter { eligible.contains($0) && seen.insert($0).inserted }
        return chosen + eligible.subtracting(seen).sorted()
    }
    public var iconConflicts: [SettingsSyncMenu] {
        menus.values.filter { $0.isPresent && $0.icon.needsChoice }.sorted { $0.id < $1.id }
    }
}

private enum SettingsSyncCoding {
    static func key<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }
    static func string<T: Encodable>(_ value: T) -> String { String(decoding: key(value), as: UTF8.self) }
}

public extension SettingsSyncPreference {
    func accepts(_ value: SettingsSyncValue) -> Bool {
        switch (self, value) {
        case (.reopenEnabled, .bool), (.automaticWindowCount, .bool), (.showAppSettings, .bool): return true
        case (.reopenInterval, .seconds(let seconds)): return seconds.isFinite && OptionReopenPreferences.intervalRange.contains(seconds)
        case (.manualWindowCount, .integer(let count)): return count >= 6
        case (.numberShortcuts, .text(let name)): return NumberShortcutAssignment(rawValue: name) != nil
        case (.theme, .text(let name)): return DeckTheme(rawValue: name) != nil
        case (.menuColor, .color(let color)), (.windowColor, .color(let color)),
             (.handoffColor, .color(let color)), (.registeredColor, .color(let color)): return color.map { $0 <= 0xFFFFFF } ?? true
        default: return false
        }
    }
}
