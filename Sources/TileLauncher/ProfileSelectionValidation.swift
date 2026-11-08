#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import DeckCore

/// Real store/mutation paths with a private suite and synthetic paths only.
enum ProfileSelectionValidation {
    private final class Reads {
        private let lock = NSLock()
        private var paths = Set<String>()
        func has(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return paths.contains(url.path) }
        func read(_ url: URL) { lock.lock(); paths.insert(url.path); lock.unlock() }
    }
    @MainActor static func verify() throws {
        let suite = "TileLauncher.ProfileSelectionValidation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw NSError(domain: "TileLauncher.ProfileSelectionValidation", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func pin(_ name: String) -> PinnedItem {
            PinnedItem(kind: .folder, path: "/Synthetic/ProfileSelection/" + name, bundleID: nil, name: name)
        }
        let a = pin("A"), b = pin("B"), c = pin("C")
        let basic = LauncherProfile(id: "default", name: "기본", items: [a])
        let work = LauncherProfile(id: "work", name: "오마", items: [b])
        let manual = LauncherProfile(id: "manual", name: "예배", items: [c])
        defaults.set(try JSONEncoder().encode([basic, work, manual]), forKey: "launcherProfiles")
        defaults.set(work.id, forKey: "manualProfileID")
        defaults.set(true, forKey: "followFocus")
        let store = SettingsStore(defaults: defaults)
        try check(store.defaultProfileID == basic.id && store.manualProfileID == work.id,
                  "Legacy migration must not promote the old manual Work target into the default role")
        store.followFocus = true; store.focusProfileID = nil
        try check(store.activeProfile.id == basic.id, "Automatic no-filter selection uses the explicit default")
        store.focusProfileID = work.id
        try check(store.activeProfile.id == work.id, "An eligible Focus still selects its existing profile")
        store.setDefaultProfile(manual.id)
        try check(store.manualProfileID == work.id && store.followFocus && store.activeProfile.id == work.id,
                  "Changing the default role cannot change manual/follow or an eligible current Focus")
        store.setDefaultProfile(work.id)
        try check(store.focusProfileID == work.id
                  && !ProfileSelection.isEligibleForFocus(work.id, profiles: store.profiles, defaultProfileID: store.defaultProfileID),
                  "Temporarily default Focus remains observed in RAM while becoming ineligible")
        store.setDefaultProfile(manual.id)
        try check(store.focusProfileID == work.id && store.activeProfile.id == work.id,
                  "Restoring a different default reactivates the retained Focus without another OS event")
        store.focusProfileID = manual.id
        try check(store.activeProfile.id == manual.id, "A default Focus reference falls back to the explicit default")
        store.selectProfile(basic.id)
        try check(!store.followFocus && store.manualProfileID == basic.id && store.defaultProfileID == manual.id,
                  "Direct selection changes manual/follow without changing the default role")
        let legacy = try JSONDecoder().decode([PinnedItem].self, from: defaults.data(forKey: "pinnedItems")!)
        try check(legacy == manual.items, "Legacy pins mirror the explicit default, not the canonical ID or active profile")
        let restored = SettingsStore(defaults: defaults)
        try check(restored.defaultProfileID == manual.id && restored.manualProfileID == basic.id && !restored.followFocus,
                  "Default and manual roles survive a real store save/reload independently")

        store.followFocus = true; store.focusProfileID = work.id
        let beforeIDs = store.profiles.map(\.id)
        try check(store.addProfile(name: "  \n", items: [a]) == nil && store.profiles.map(\.id) == beforeIDs,
                  "An empty confirmed name creates nothing")
        let clone = store.addProfile(name: "  복제  ", items: [a, c])!
        try check(store.profile(id: clone)?.name == "복제" && store.items(profileID: clone) == [a, c]
                  && store.manualProfileID == basic.id && store.defaultProfileID == manual.id && store.followFocus,
                  "Creating a captured-item clone cannot select it or modify either role")
        try check(!store.removeProfile(id: manual.id), "The current default role is protected")
        store.setDefaultProfile(clone)
        try check(store.removeProfile(id: basic.id) && store.manualProfileID == clone && store.followFocus,
                  "The former canonical default is deletable; deleting manual falls back without disabling automatic")

        // Explicit editor targets must remain independent of a different active Focus.
        store.setItems([a, c], profileID: manual.id)
        store.move(c, by: -1, profileID: manual.id)
        store.setOpenMode(.finder, for: a.id, profileID: manual.id)
        try check(store.items(profileID: manual.id).map(\.id) == [c.id, a.id]
                  && store.items(profileID: manual.id).last?.openMode == .finder
                  && store.items(profileID: work.id) == [b], "Explicit mutations cannot edit the active Focus profile")
        let beforeDock = store.items(profileID: manual.id)
        store.previewDockImport(.init(items: [pin("Dock")], skipped: 0), profileID: manual.id)
        let change = store.dockImportPreview!
        store.applyDockImport(change)
        try check(store.canUndoDockImport(profileID: manual.id) && !store.canUndoDockImport(profileID: work.id)
                  && store.items(profileID: work.id) == [b], "Dock preview/apply/undo belongs to its captured editor target")
        store.undoDockImport(profileID: manual.id)
        try check(store.items(profileID: manual.id) == beforeDock, "Targeted Dock undo restores the exact previous items/modes")
        store.previewDockImport(.init(items: [pin("StaleDock")], skipped: 0), profileID: manual.id)
        let stale = store.dockImportPreview!
        store.setItems([c], profileID: manual.id)
        store.applyDockImport(stale)
        try check(store.items(profileID: manual.id) == [c] && store.items(profileID: work.id) == [b],
                  "A stale Dock confirmation must not overwrite newer edits or another active profile")

        // Exercise @Published's emitted values, including default-only changes,
        // using injected readers; no filesystem image or installed app reads.
        let reads = Reads()
        let warmer = IconReadAhead(settings: store, hasApp: reads.has, readApp: reads.read,
                                   hasMenu: { _ in true }, readMenu: { _ in })
        defer { warmer.stop() }
        func wait(_ item: PinnedItem) throws {
            let end = Date().addingTimeInterval(2)
            while !reads.has(item.url), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            try check(reads.has(item.url), "Read-ahead must follow emitted selection state")
        }
        try wait(b)
        let fallback = pin("NewDefault")
        store.setItems([fallback], profileID: clone)
        store.focusProfileID = nil
        try wait(fallback)
        let newRole = pin("RoleChange")
        store.setItems([newRole], profileID: manual.id)
        store.setDefaultProfile(manual.id)
        try wait(newRole)
        store.selectProfile(work.id)
        try wait(b)

        // The older integration fixture must share the new fallback contract.
        try PreviewFixture(theme: .classic, registeredCount: 0).verifyFocusSelection()
        print("Profile selection: isolated migration/save/reload, independent roles, creation/deletion, explicit editor mutations, Dock stale/undo and emitted-value icon prewarm passed.")
    }
}
#endif
