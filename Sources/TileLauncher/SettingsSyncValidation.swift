#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import DeckCore

/// Isolated local persistence checks. Never creates a signed CloudKit container,
/// registers an account, observes app menus, or reads the user's preferences.
enum SettingsSyncValidation {
    @MainActor static func verify() throws {
        let suite = "TileLauncher.SyncValidation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "SettingsSyncValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let file = root.appendingPathComponent("state.json")
        let source = SettingsStore(defaults: defaults)
        let coordinator = SettingsSyncCoordinator(settings: source, defaults: defaults, file: file)
        let profiles = source.profiles
        source.theme = .classic
        let command = MenuCommand(appID: "validation.app", appName: "Validation", path: ["File", "Open"])
        source.addCommand(command)
        let saved = try Data(contentsOf: file)
        source.recordUse(command.id)
        let afterUsage = try Data(contentsOf: file)
        try check(afterUsage == saved, "Runtime usage rewrote the sync journal")
        source.setSymbol("gear", for: command.id)
        let changed = try Data(contentsOf: file)
        try check(changed != saved, "User icon edit did not persist")
        source.syncStatus.clearIconEdits?()
        var edited = MenuCommand(appID: "validation.app", appName: "Validation", path: ["File", "Edited"], isPinned: false)
        edited.isAutomatic = true
        var collected = MenuCommand(appID: "validation.app", appName: "Validation", path: ["File", "Collected"], isPinned: false)
        collected.isAutomatic = true
        source.commands += [edited, collected]
        source.setSymbol("star", for: edited.id)
        source.syncStatus.clearIconEdits?()
        try check(source.sharedMenus.contains(edited.id) && !source.sharedMenus.contains(collected.id), "Edited collected menu was not shared")
        source.clearCapturedMenus(appID: "validation.app")
        try check(source.commands.contains { $0.id == edited.id } && !source.commands.contains { $0.id == collected.id },
                  "Clearing collection history deleted a shared edited menu or kept local history")
        coordinator.shutdown()
        let reopened = SettingsSyncCoordinator(settings: source, defaults: defaults, file: file)
        try check(source.commands.first?.symbol == "gear" && source.profiles == profiles, "Restore lost editable data or modified profiles")
        reopened.shutdown()
        let bad = root.appendingPathComponent("corrupt.json")
        let original = Data("not a valid sync file".utf8)
        try original.write(to: bad)
        let corrupt = SettingsSyncCoordinator(settings: source, defaults: defaults, file: bad)
        source.theme = .glass
        try check(source.syncStatus.error != nil, "Corrupt sync file was silently replaced")
        let corruptBytes = try Data(contentsOf: bad)
        try check(corruptBytes == original, "Corrupt sync evidence was overwritten")
        corrupt.shutdown()
        try verifyStartupAndDisk(root: root, check: check)
        try verifyUnchangedApplyAndColors(check: check)
        try SettingsSyncCoordinator.verifyOfflineCoordinator(root: root)
    }
    /// Allows ordinary editor/run-loop updates; checkpoints are synchronous.
    @MainActor private static func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    private static func journal(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }
    private static func journalTheme(_ url: URL) throws -> String? {
        let observed = try journal(url)["observed"] as? [String: Any]
        let theme = (observed?["preferences"] as? [String: Any])?["theme"] as? [String: Any]
        return (theme?["text"] as? [String: Any])?["_0"] as? String
    }
    @MainActor private static func verifyStartupAndDisk(root: URL, check: (@autoclosure () -> Bool, String) throws -> Void) throws {
        func fresh(_ name: String) -> (UserDefaults, URL, String) {
            let suite = "TileLauncher.SyncValidation." + name + "." + UUID().uuidString
            return (UserDefaults(suiteName: suite)!, root.appendingPathComponent(name + ".json"), suite)
        }
        // An older version deliberately restoring the previous value is kept.
        var (defaults, file, suite) = fresh("revert")
        var store = SettingsStore(defaults: defaults)
        store.theme = .glass
        var sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        store.theme = .classic
        let savedCommit = try journal(file)["commit"] as? String
        try check(savedCommit != nil && defaults.string(forKey: "settingsSyncCheckpoint") == savedCommit,
                  "Defaults completion checkpoint waited for another run-loop turn")
        sync.shutdown()
        defaults.set(DeckTheme.glass.rawValue, forKey: "appearanceTheme") // old app: classic → glass
        store = SettingsStore(defaults: defaults)
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        try check(store.theme == .glass, "Reverting to the previous value in an older version was treated as an interrupted write")
        let importedTheme = try journalTheme(file)
        try check(importedTheme == DeckTheme.glass.rawValue, "External edit was not journaled")
        let replicaTheme = ((try journal(file)["replica"] as? [String: Any])?["snapshot"] as? [String: Any])?["preferences"] as? [String: Any]
        let stamp = (replicaTheme?["theme"] as? [String: Any])?["stamp"] as? [String: Any]
        try check(stamp != nil && stamp?["date"] == nil, "External edit received an invented edit time")
        sync.shutdown(); defaults.removePersistentDomain(forName: suite)

        // A journaled change whose defaults write never completed is replayed.
        (defaults, file, suite) = fresh("interrupted")
        store = SettingsStore(defaults: defaults); store.theme = .glass
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        store.theme = .classic; drain(); sync.shutdown()
        defaults.set(DeckTheme.glass.rawValue, forKey: "appearanceTheme")
        defaults.set("never-completed", forKey: "settingsSyncCheckpoint")
        store = SettingsStore(defaults: defaults)
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        try check(store.theme == .classic, "Interrupted defaults write was not replayed from the journal")
        sync.shutdown(); defaults.removePersistentDomain(forName: suite)

        // A failed journal write keeps edits in memory and recovers on the next save.
        (defaults, file, suite) = fresh("diskfull")
        var failing = false
        store = SettingsStore(defaults: defaults); store.theme = .glass
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file, write: { data, url in
            if failing { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        drain()
        let checkpoint = defaults.string(forKey: "settingsSyncCheckpoint")
        failing = true
        store.theme = .classic; drain()
        try check(store.syncStatus.error != nil, "Journal write failure was silent")
        let unchangedTheme = try journalTheme(file)
        try check(unchangedTheme == DeckTheme.glass.rawValue, "Failed write changed the journal")
        try check(defaults.string(forKey: "settingsSyncCheckpoint") == checkpoint, "Checkpoint advanced past an unwritten journal")
        failing = false
        store.showAppSettingsTile.toggle(); drain()
        let recoveredTheme = try journalTheme(file)
        try check(store.syncStatus.error == nil && recoveredTheme == DeckTheme.classic.rawValue,
                  "Edit made during the failure was lost after recovery")
        sync.shutdown(); defaults.removePersistentDomain(forName: suite)

        // A future-schema journal is preserved and never applied, even when the
        // rest of it decodes with this version's types.
        (defaults, file, suite) = fresh("future")
        store = SettingsStore(defaults: defaults); store.theme = .glass
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        store.theme = .classic; drain(); sync.shutdown()
        var object = try journal(file); object["schema"] = 99
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: file)
        defaults.set(DeckTheme.glass.rawValue, forKey: "appearanceTheme")
        store = SettingsStore(defaults: defaults)
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        store.numberShortcuts = store.numberShortcuts == .registeredFirst ? .windowsFirst : .registeredFirst
        let preserved = try Data(contentsOf: file)
        try check(store.theme == .glass && preserved == future, "Future journal changed defaults or was overwritten")
        sync.shutdown(); defaults.removePersistentDomain(forName: suite)

        // Valid JSON with a malformed local snapshot is a local read error,
        // never a reason to quarantine every valid incoming cloud record.
        (defaults, file, suite) = fresh("semantic-corruption")
        store = SettingsStore(defaults: defaults); store.theme = .glass
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        sync.shutdown()
        var malformed = try JSONDecoder().decode(SettingsSyncReplica.self, from:
            JSONSerialization.data(withJSONObject: try journal(file)["replica"]!))
        malformed.snapshot.orders["validation.app"] = .init(["duplicate", "duplicate"],
            stamp: .init(date: nil, device: "validation", sequence: 1))
        var corruptObject = try journal(file)
        corruptObject["replica"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(malformed))
        let corruptData = try JSONSerialization.data(withJSONObject: corruptObject)
        try corruptData.write(to: file)
        store = SettingsStore(defaults: defaults)
        sync = SettingsSyncCoordinator(settings: store, defaults: defaults, file: file)
        let unchanged = try Data(contentsOf: file)
        try check(store.theme == .glass && store.syncStatus.error != nil && unchanged == corruptData,
                  "Invalid local snapshot was applied or overwritten")
        sync.shutdown(); defaults.removePersistentDomain(forName: suite)
    }
    @MainActor private static func verifyUnchangedApplyAndColors(check: (@autoclosure () -> Bool, String) throws -> Void) throws {
        let suite = "TileLauncher.SyncValidation.apply." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var saves = 0
        store.onPersistentChange = { saves += 1 }
        store.applySyncProjection(store.syncProjection)
        try check(saves == 0, "Applying unchanged synced values rewrote UserDefaults")
        for hex: UInt32 in [0, 1, 0x7F7F7F, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF] {
            store.tileColors.menus = TileColor(hex)
            let projected = store.syncProjection.preferences["menuColor"]
            try check(projected == .color(hex), "Color \(hex) changed while projected")
            store.tileColors.menus = nil
            store.applySyncProjection(.init(preferences: ["menuColor": .color(hex)], commands: store.commands))
            try check(store.tileColors.menus?.hex == hex, "Color \(hex) changed after a sync round trip")
        }
    }
}
#endif
