import Foundation

/// Sync lifecycle decisions kept free of CloudKit so they can be tested.
public enum SettingsSyncLifecycle {
    /// CKAccountStatus, plus the account key when it could be read.
    public enum AccountStatus: Equatable {
        case available(String?), noAccount, restricted, temporarilyUnavailable, couldNotDetermine
    }
    public enum AccountDecision: Equatable { case none, connect, changed }
    /// Only a readable, different account or a sign-out counts as a change.
    /// An unknown or temporarily unavailable status changes nothing: CloudKit
    /// says not to delete cached data or enqueue work and to wait for the
    /// next account-changed notification instead.
    public static func accountDecision(previous: String?, status: AccountStatus) -> AccountDecision {
        switch status {
        case .available(let key?): return previous == nil || previous == key ? .connect : .changed
        case .noAccount: return previous == nil ? .none : .changed
        case .available(nil), .restricted, .temporarilyUnavailable, .couldNotDetermine: return .none
        }
    }

    public enum ZoneDeletion: Equatable { case deletedByApp, purgedByUser, encryptedDataReset, unknown }
    public enum ZoneDeletionAction: Equatable { case recreate, stopWithoutResend }
    /// `purged` (Settings app) and `encryptedDataReset` must never be resent;
    /// an unknown reason is treated the same way.
    public static func action(for deletion: ZoneDeletion) -> ZoneDeletionAction {
        deletion == .deletedByApp ? .recreate : .stopWithoutResend
    }

    public enum Startup: Equatable { case consistent, interruptedWrite, externalEdit }
    /// The journal is written (with a new commit nonce) before UserDefaults,
    /// and the nonce is copied into UserDefaults only after every key was
    /// written. A journal nonce the defaults never received proves an
    /// interrupted write (replay the journal). With a matching nonce, any
    /// difference was made outside the journal — by an older app version,
    /// which leaves the unknown key untouched, or after a failed journal
    /// write — and must be kept. Values alone cannot tell these apart: an
    /// older version may have deliberately restored the previous value.
    /// A journal without a nonce (earlier internal format) keeps defaults.
    public static func startup(current: SettingsSyncProjection, observed: SettingsSyncProjection,
                               journalCommit: String?, defaultsCheckpoint: String?, managed: Set<UUID>) -> Startup {
        if SyncedView(current, managed: managed) == SyncedView(observed, managed: managed) { return .consistent }
        if let journalCommit, defaultsCheckpoint != journalCommit { return .interruptedWrite }
        return .externalEdit
    }
    /// Only fields that synchronize: runtime counters never count as an edit.
    struct SyncedView: Equatable {
        struct Menu: Equatable { let id: UUID; let appID: String; let path: [String]; let pinned: Bool; let symbol: String?; let execution: MenuExecutionSelection }
        let preferences: [String: SettingsSyncValue]
        let menus: [Menu]
        init(_ projection: SettingsSyncProjection, managed: Set<UUID>) {
            preferences = projection.preferences.filter { SettingsSyncPreference(rawValue: $0.key) != nil }
            // Same eligibility as capture: path-based app IDs never sync, so
            // they are never journaled and must not count as an outside edit.
            menus = projection.commands.filter {
                !$0.appID.hasPrefix("/") && (managed.contains($0.id) || !$0.isAutomatic || $0.isPinned || $0.symbol != nil)
            }.map { .init(id: $0.id, appID: $0.appID, path: $0.path, pinned: $0.isPinned, symbol: $0.symbol, execution: $0.executionSelection) }
        }
    }
}

public extension SettingsSyncReplica {
    /// Records changes made outside the journal. Their real edit time is
    /// unknown, so every stamp this import creates is legacy (no date) rather
    /// than an invented current time.
    mutating func importExternal(before: SettingsSyncProjection, after: SettingsSyncProjection) {
        let mark = sequence, own = device
        capture(before: before, after: after, at: Date())
        // A sequence rollover inside capture switches to a new device ID;
        // every stamp of that new ID was created by this import as well.
        let renewed = device != own ? device : nil
        func legacy(_ stamp: SettingsSyncStamp) -> SettingsSyncStamp {
            let created = (stamp.device == own && stamp.sequence > mark) || stamp.device == renewed
            return created ? .init(date: nil, device: stamp.device, sequence: stamp.sequence) : stamp
        }
        for (key, field) in snapshot.preferences { snapshot.preferences[key]!.stamp = legacy(field.stamp) }
        for (key, field) in snapshot.orders { snapshot.orders[key]!.stamp = legacy(field.stamp) }
        for (id, value) in snapshot.menus {
            var menu = value
            menu.presence.stamp = legacy(menu.presence.stamp)
            menu.pinned.stamp = legacy(menu.pinned.stamp)
            if let execution = menu.execution { menu.execution?.stamp = legacy(execution.stamp) }
            menu.icon = SettingsSyncIcon(menu.icon.edits.map {
                SettingsSyncIconEdit(symbol: $0.symbol, stamp: legacy($0.stamp), observed: $0.observed)
            })
            snapshot.menus[id] = menu
        }
    }
}
