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
        let coordinator = SettingsSyncCoordinator(settings: source, file: file)
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
        let reopened = SettingsSyncCoordinator(settings: source, file: file)
        try check(source.commands.first?.symbol == "gear" && source.profiles == profiles, "Restore lost editable data or modified profiles")
        reopened.shutdown()
        let bad = root.appendingPathComponent("corrupt.json")
        let original = Data("not a valid sync file".utf8)
        try original.write(to: bad)
        let corrupt = SettingsSyncCoordinator(settings: source, file: bad)
        source.theme = .glass
        try check(source.syncStatus.error != nil, "Corrupt sync file was silently replaced")
        let corruptBytes = try Data(contentsOf: bad)
        try check(corruptBytes == original, "Corrupt sync evidence was overwritten")
        corrupt.shutdown()
    }
}
#endif
