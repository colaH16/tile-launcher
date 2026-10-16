import AppKit
import DeckCore

enum DockImportValidation {
    @MainActor static func verify() throws -> DockImportChange {
        let suite = "dev.cola16.TileLauncher.preview.dock-import." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "DockImportValidation", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let store = SettingsStore(defaults: defaults)
        let finder = PinnedItem(kind: .app, path: "/System/Library/CoreServices/Finder.app",
                                bundleID: "com.apple.finder", name: "Finder")
        let folder = PinnedItem(kind: .folder, path: "/tmp", bundleID: nil, name: "작업 자료", openMode: .finder)
        let safari = PinnedItem(kind: .app, path: "/Applications/Safari.app", bundleID: "com.apple.Safari", name: "Safari")
        let notes = PinnedItem(kind: .app, path: "/System/Applications/Notes.app", bundleID: "com.apple.Notes", name: "메모")
        store.profiles = [LauncherProfile(id: "default", name: "기본", items: [folder, finder]),
                          LauncherProfile(id: "other", name: "별도 구성", items: [])]
        store.selectProfile("default")
        let original = store.profiles
        let savedBefore = defaults.data(forKey: "launcherProfiles")
        let imported = DockImportResult(items: [finder, safari, notes], skipped: 1)
        store.previewDockImport(imported, profileID: "default")
        guard let preview = store.dockImportPreview else { throw NSError(domain: "Missing preview", code: 1) }
        try check(store.profiles == original && defaults.data(forKey: "launcherProfiles") == savedBefore,
                  "Preview wrote registered items before confirmation")
        store.cancelDockImport()
        try check(store.dockImportPreview == nil && store.profiles == original
                  && defaults.data(forKey: "launcherProfiles") == savedBefore, "Cancel changed saved items")
        store.previewDockImport(imported, profileID: "default")
        let next = store.dockImportPreview!
        store.selectProfile("other")
        store.applyDockImport(next)
        try check(store.profiles[0].items == next.after && store.profiles[1].items.isEmpty && !store.canUndoDockImport,
                  "Import followed the newly selected profile")
        try check(store.dockImportMessage == nil, "Import status appeared on the wrong profile")
        store.selectProfile("default")
        try check(store.canUndoDockImport, "Confirmed import has no undo")
        try check(store.dockImportMessage?.contains("기본") == true, "Import status lost its target profile")
        let restored = SettingsStore(defaults: defaults)
        try check(restored.profiles == store.profiles, "Confirmed import was not saved")
        store.previewDockImport(.init(items: [notes], skipped: 0), profileID: "default")
        store.cancelDockImport()
        try check(store.canUndoDockImport, "Cancelling a new preview lost previous undo")
        store.undoDockImport()
        try check(store.profiles == original && !store.canUndoDockImport, "Undo did not restore exact original profiles")
        try check(SettingsStore(defaults: defaults).profiles == original, "Undo was not saved")
        store.previewDockImport(imported, profileID: "default")
        let stale = store.dockImportPreview!
        store.setItems([folder], profileID: "default")
        store.applyDockImport(stale)
        try check(store.profiles[0].items == [folder], "Stale preview overwrote newer edits")
        store.previewDockImport(imported, profileID: "default")
        store.applyDockImport(store.dockImportPreview!)
        store.setOpenMode(.overlay, for: folder.id)
        try check(!store.canUndoDockImport, "Undo would overwrite edits after import")
        return preview
    }
}
