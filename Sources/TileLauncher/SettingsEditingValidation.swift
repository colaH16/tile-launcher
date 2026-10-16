import AppKit
import DeckCore

enum SettingsEditingValidation {
    @MainActor static func verify() throws -> (SettingsStore, SettingsEditingSession) {
        let suite = "dev.cola16.TileLauncher.preview.settings-edit." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        // The preview objects are in-memory snapshots; no data is needed after this check.
        defer { defaults.removePersistentDomain(forName: suite) }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "SettingsEditingValidation", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let source = SettingsStore(defaults: defaults)
        source.theme = .classic
        let original = MenuCommand(appID: "preview.editor", appName: "편집기", path: ["파일", "열기"], isPinned: false)
        source.commands = [original]
        let baseProfiles = source.profiles
        var additions = 0, visibilityChanges = 0
        source.onMenuAdded = { _ in additions += 1 }
        source.onAppSettingsVisibilityChanged = { _ in visibilityChanges += 1 }
        let savedBefore = defaults.persistentDomain(forName: suite)! as NSDictionary
        let edit = SettingsEditingSession(source: source)
        edit.appearance.theme = .glass
        edit.appearance.tileColors.menus = TileColor(0x398B52)
        edit.menus.showAppSettingsTile = false
        edit.menus.menuCapture.enabled = false
        let extra = MenuCommand(appID: original.appID, appName: original.appName, path: ["파일", "새 창"])
        edit.menus.addCommand(extra)
        edit.registered.addProfile(name: "편집 중 프로필", copyingCurrent: false)
        try check(source.theme == .classic && source.commands == [original] && source.profiles == baseProfiles
                  && savedBefore.isEqual(to: defaults.persistentDomain(forName: suite)!),
                  "Editing a tab wrote live settings")
        try check(additions == 0 && visibilityChanges == 0, "Draft editing invoked production callbacks")
        try check([SettingsTab.appearance, .menus, .registered].allSatisfy(edit.hasChanges), "Tab drafts were not independent")
        source.manualCount = 37
        source.optionTriggerEnabled = false
        try check(defaults.integer(forKey: "manualWindowCount") == 37
                  && !defaults.bool(forKey: "optionTriggerEnabled"), "General settings stopped saving immediately")
        edit.save(.appearance)
        try check(source.theme == .glass && source.tileColors.menus == TileColor(0x398B52)
                  && source.commands == [original] && source.profiles == baseProfiles,
                  "Saving appearance committed another tab")
        try check(source.manualCount == 37 && !source.optionTriggerEnabled, "Saving a draft restored stale General values")
        edit.cancel(.menus)
        try check(!edit.hasChanges(.menus) && edit.hasChanges(.registered)
                  && source.showAppSettingsTile && source.menuCapture.enabled,
                  "Cancel affected another tab or a live setting")
        edit.save(.registered)
        try check(source.profiles.count == baseProfiles.count + 1
                  && SettingsStore(defaults: defaults).profiles == source.profiles, "Profile Save was not persisted")
        edit.appearance.tileColors.windows = TileColor(0x2255AA)
        edit.cancel(.appearance)
        try check(edit.appearance.tileColors == source.tileColors && edit.appearance.theme == .glass,
                  "Cancel did not restore the latest saved appearance")
        edit.menus.togglePin(original.id)
        source.recordUse(original.id)
        let captured = CapturedMenu(appID: original.appID, appName: original.appName, path: ["파일", "저장"])
        source.recordCapturedMenu(captured)
        edit.synchronize()
        try check(edit.menus.commands.contains(where: { $0.path == captured.identity.path }),
                  "Fresh captures were hidden/lost while editing")
        edit.menus.showAppSettingsTile = false
        edit.menus.menuRecentDaysInput = "60"
        edit.menus.menuFrequentDaysInput = "120"
        edit.menus.updateMenuHistoryInput()
        edit.save(.menus)
        try check(source.commands.first(where: { $0.id == original.id })?.useCount == 1
                  && source.commands.first(where: { $0.id == original.id })?.isPinned == true
                  && source.commands.contains(where: { $0.path == captured.identity.path }),
                  "Menu Save lost live usage, pins or new captures")
        try check(!source.showAppSettingsTile && visibilityChanges == 1
                  && source.menuHistory == .init(recentDays: 60, frequentDays: 120),
                  "Menu Save did not apply settings/history input")
        let beforeInvalid = source.menuHistory
        edit.menus.menuRecentDaysInput = ""
        try check(edit.hasChanges(.menus) && !edit.canSave(.menus), "Invalid period could be saved")
        edit.cancel(.menus)
        try check(edit.menus.validMenuHistoryInput == beforeInvalid && !edit.hasChanges(.menus),
                  "Invalid text survived Change Cancel")
        edit.menus.addCommand(extra)
        try check(additions == 1, "Draft menu addition invoked live icon collection")
        edit.save(.menus)
        try check(additions == 2 && source.commands.contains(where: { $0.id == extra.id }),
                  "Saved menu addition did not invoke the live callback once")
        edit.menus.removeCommand(extra)
        if let index = source.commands.firstIndex(where: { $0.id == extra.id }) {
            source.commands[index].resourceBinding = .init(
                identity: .init(appID: extra.appID, archive: "MainMenu.nib", keys: ["shell", "new-window"]),
                paths: [extra.path, ["File", "New Window"]])
        }
        edit.save(.menus)
        try check(!source.commands.contains(where: { $0.id == extra.id })
                  && source.menuCapture.excludedMenus.contains(.init(appID: extra.appID, path: ["File", "New Window"])),
                  "Saving a deletion lost newly resolved language exclusions")
        edit.menus.refreshingMenuIcons.insert("preview.editor")
        try check(edit.hasChanges(.menus) && !edit.canSave(.menus), "In-flight icon refresh could not be cancelled")
        edit.cancel(.menus)
        try check(edit.menus.refreshingMenuIcons.isEmpty, "Cancel left the icon refresh busy")
        let id = source.profiles[0].id
        edit.registered.profiles[0].name = "편집한 이름"
        source.profiles[0].name = "외부에서 바뀐 이름"
        edit.save(.registered)
        try check(source.profiles[0].name == "외부에서 바뀐 이름" && edit.errors[.registered] != nil,
                  "Conflicting profile Save overwrote the live list")
        edit.cancel(.registered)
        try check(edit.registered.profiles[0].id == id && !edit.hasChanges(.registered),
                  "Cancel did not reload the current profile")
        edit.registered.previewDockImport(.init(items: [.init(kind: .folder, path: "/tmp", bundleID: nil, name: "작업 자료")], skipped: 0),
                                         profileID: edit.registered.activeProfile.id)
        let dockBefore = source.profiles
        if let preview = edit.registered.dockImportPreview { edit.registered.applyDockImport(preview) }
        try check(source.profiles == dockBefore && edit.hasChanges(.registered), "Dock staging bypassed tab Save")
        edit.cancel(.registered)
        try check(source.profiles == dockBefore && !edit.hasChanges(.registered), "Cancel retained a staged Dock import")
        edit.activate()
        source.recordUse(original.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let openCount = edit.menus.commands.first(where: { $0.id == original.id })!.useCount
        try check(openCount == source.commands.first(where: { $0.id == original.id })!.useCount,
                  "Open editor missed a runtime update")
        edit.pause()
        source.recordUse(original.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try check(edit.menus.commands.first(where: { $0.id == original.id })!.useCount == openCount,
                  "Closed editor continued refreshing drafts")
        edit.activate()
        try check(edit.menus.commands.first(where: { $0.id == original.id })!.useCount == openCount + 1,
                  "Reopening did not refresh live history")
        edit.pause()
        edit.appearance.tileColors.windows = TileColor(0x3881B0)
        edit.menus.showAppSettingsTile = true
        edit.registered.addProfile(name: "미저장 프로필", copyingCurrent: false)
        print("Per-tab edits: General immediate; independent Save/Cancel, no draft persistence/callbacks, live menu history/captures preserved, profile conflicts and Dock staging passed.")
        return (source, edit)
    }
}
