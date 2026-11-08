#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import DeckCore
import SwiftUI

/// Exercises the real window-local editor and views with synthetic settings.
/// No live Focus query, user defaults, Dock read, permission request or app launch.
enum ProfileSettingsUIValidation {
    @MainActor static func verify(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "dev.cola16.TileLauncher.preview.profile-settings." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "ProfileSettingsUIValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        struct Roles: Equatable {
            let defaultID: String
            let manualID: String
            let follows: Bool
            init(_ store: SettingsStore) {
                defaultID = store.defaultProfileID; manualID = store.manualProfileID; follows = store.followFocus
            }
        }
        let first = PinnedItem(kind: .folder, path: "/Synthetic/ProfileA", bundleID: nil,
                               name: "기본 폴더", openMode: .finder)
        let second = PinnedItem(kind: .folder, path: "/Synthetic/ProfileB", bundleID: nil,
                                name: "업무 폴더", openMode: .finder)
        let third = PinnedItem(kind: .folder, path: "/Synthetic/ProfileC", bundleID: nil,
                               name: "예배 폴더", openMode: .finder)
        let extra = PinnedItem(kind: .folder, path: "/Synthetic/New", bundleID: nil,
                               name: "추가 폴더", openMode: .finder)
        let source = SettingsStore(defaults: defaults)
        source.batchSave {
            source.profiles = [LauncherProfile(id: "default", name: "기본 구성", items: [first]),
                               LauncherProfile(id: "work", name: "업무", items: [second]),
                               LauncherProfile(id: "worship", name: "예배", items: [third])]
            source.defaultProfileID = "default"
            source.manualProfileID = "work"
            source.followFocus = true
        }
        source.focusProfileID = "work"
        let sourceRoles = Roles(source), originalProfiles = source.profiles
        let savedProfiles = defaults.data(forKey: "launcherProfiles")
        let editor = SettingsEditingSession(source: source)
        let navigation = SettingsNavigation()
        navigation.tab = .registered

        editor.selectEditingProfile("default")
        try check(!editor.hasChanges(.registered) && Roles(editor.registered) == sourceRoles,
                  "Browsing an editor profile changed persistent roles or made the tab dirty")
        try check(editor.registered.items(profileID: editor.editorProfileID) == [first]
                  && editor.registered.activeProfile.id == "work", "Editor target still follows activeProfile")
        source.focusProfileID = "worship"
        editor.synchronize()
        try check(editor.editorProfileID == "default" && !editor.hasChanges(.registered),
                  "A Focus update redirected the editing target or dirtied the tab")
        try check(Roles(source) == sourceRoles && defaults.data(forKey: "launcherProfiles") == savedProfiles,
                  "Browsing/Focus synchronization changed saved selections or profiles")

        // Manipulate the same Binding supplied to the actual production Toggle,
        // without sending key/mouse events to any app or global accessibility.
        let automaticSelection = editor.followFocusBinding
        automaticSelection.wrappedValue = false
        try check(!editor.registered.followFocus && source.followFocus && defaults.bool(forKey: "followFocus")
                  && editor.hasChanges(.registered), "Automatic-selection Toggle wrote live settings before Save")
        editor.cancel(.registered)
        try check(automaticSelection.wrappedValue && source.followFocus && defaults.bool(forKey: "followFocus"),
                  "Cancel did not discard the production Toggle edit")
        automaticSelection.wrappedValue = false
        editor.save(.registered)
        try check(!source.followFocus && !defaults.bool(forKey: "followFocus") && !editor.hasChanges(.registered),
                  "Production Toggle edit was not applied by the registered tab Save")
        automaticSelection.wrappedValue = true
        editor.save(.registered)

        // Default role changes are buffered; tab navigation and another tab's
        // save cannot commit them, while Cancel restores the actual saved role.
        editor.selectEditingProfile("worship")
        editor.setEditingProfileAsDefault()
        navigation.tab = .menus; navigation.tab = .registered
        editor.save(.appearance)
        try check(editor.editorProfileID == "worship" && editor.registered.defaultProfileID == "worship"
                  && source.defaultProfileID == "default" && editor.hasChanges(.registered),
                  "Tab navigation or another tab save committed/lost the default draft")
        try check(editor.registered.manualProfileID == "work" && editor.registered.followFocus,
                  "Default role edit changed manual/Focus selection")
        editor.cancel(.registered)
        try check(!editor.hasChanges(.registered) && editor.registered.defaultProfileID == "default"
                  && editor.editorProfileID == "worship", "Cancel changed the local editor or retained a role edit")

        editor.beginProfileCreation(copyingCurrent: false)
        let countBeforeName = editor.registered.profiles.count
        editor.confirmProfileCreation(name: " \n ")
        try check(editor.profileCreation != nil && editor.registered.profiles.count == countBeforeName,
                  "Whitespace-only name confirmed or dismissed a creation")
        editor.cancelProfileCreation()
        try check(!editor.hasChanges(.registered) && source.profiles == originalProfiles,
                  "Cancelling the name dialog changed settings")

        // Duplicate uses the button-time value, even if its source is edited
        // and Focus changes while the dialog is open.
        editor.selectEditingProfile("default")
        editor.beginProfileCreation(copyingCurrent: true)
        guard let request = editor.profileCreation else { throw NSError(domain: "Missing creation", code: 1) }
        try check(request.sourceProfileID == "default" && request.copiedItems == [first],
                  "Duplicate did not capture the editing profile")
        editor.registered.setItems([first, extra], profileID: "default")
        source.focusProfileID = "work"
        editor.synchronize()
        editor.confirmProfileCreation(name: "  복제 구성  ")
        let cloneID = editor.editorProfileID
        try check(editor.registered.profile(id: cloneID)?.name == "복제 구성"
                  && editor.registered.items(profileID: cloneID) == [first],
                  "Duplicate used a later active profile/items or failed to trim the name")
        try check(Roles(editor.registered) == sourceRoles && Roles(source) == sourceRoles
                  && source.profiles == originalProfiles, "Creation changed live settings or draft selection roles")
        editor.cancel(.registered)
        try check(editor.profileCreation == nil && editor.editorProfileID == "default"
                  && editor.registered.profiles == originalProfiles, "Cancel retained a new profile or invalid editor ID")

        editor.beginProfileCreation(copyingCurrent: false)
        editor.confirmProfileCreation(name: "빈 구성")
        let emptyID = editor.editorProfileID
        try check(editor.registered.items(profileID: emptyID).isEmpty && source.profiles == originalProfiles,
                  "Empty creation copied active items or committed early")
        editor.save(.registered)
        let restored = SettingsStore(defaults: defaults)
        try check(restored.profile(id: emptyID) != nil && Roles(restored) == sourceRoles
                  && editor.editorProfileID == emptyID && !editor.hasChanges(.registered),
                  "Registered save did not persist the draft or persisted its editor selection as a runtime role")

        // Current default is protected; the literal legacy ID is not a role.
        editor.selectEditingProfile("worship")
        editor.setEditingProfileAsDefault()
        editor.save(.registered)
        editor.deleteEditingProfile()
        try check(editor.registered.profile(id: "worship") != nil && !editor.hasChanges(.registered),
                  "Current default could be deleted")
        editor.selectEditingProfile("default")
        editor.deleteEditingProfile()
        try check(editor.registered.profile(id: "default") == nil && editor.editorProfileID == "worship",
                  "Legacy ID remained undeletable or deleted editor target did not recover")
        editor.cancel(.registered)

        // Every Dock action carries an explicit target; switching editor and
        // Focus after preview cannot redirect apply/undo or its status.
        let beforeDock = editor.registered.items(profileID: "default")
        editor.selectEditingProfile("default")
        editor.registered.previewDockImport(.init(items: [extra], skipped: 0), profileID: editor.editorProfileID)
        guard let change = editor.registered.dockImportPreview else { throw NSError(domain: "Missing Dock preview", code: 1) }
        try check(!editor.canBeginProfileCreation, "Name dialog could overlap a Dock preview")
        editor.beginProfileCreation(copyingCurrent: false)
        try check(editor.profileCreation == nil, "Creation ignored the Dock sheet guard")
        editor.selectEditingProfile("work")
        source.focusProfileID = "worship"
        editor.synchronize()
        editor.registered.applyDockImport(change)
        try check(editor.registered.items(profileID: "default") == change.after
                  && editor.registered.items(profileID: "work") == [second]
                  && editor.registered.dockImportMessage(profileID: "work") == nil
                  && editor.registered.canUndoDockImport(profileID: "default"),
                  "Dock confirmation/status followed active or current editing profile")
        editor.registered.undoDockImport(profileID: "default")
        try check(editor.registered.items(profileID: "default") == beforeDock
                  && source.items(profileID: "default") == beforeDock, "Explicit Dock undo changed another profile or live settings")
        editor.cancel(.registered)

        // Actual production views render in a never-shown native host. These
        // synthetic defaults have no live sync/menu/permission callbacks.
        editor.selectEditingProfile("work")
        let view = SettingsEditorPane(session: editor, draft: editor.registered, tab: .registered) { draft in
            RegisteredProfileSettingsPane(settings: draft, editor: editor)
        }
        for dark in [false, true] {
            try PreviewExport.save(view.padding(SettingsWindowLayout.outerPadding).frame(width: 980, height: 760)
                .foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light), dark: dark,
                                   to: directory.appendingPathComponent("profile-settings-\(dark ? "dark" : "light").png"))
            editor.selectEditingProfile(source.defaultProfileID)
            try PreviewExport.save(view.padding(SettingsWindowLayout.outerPadding).frame(width: 980, height: 760)
                .foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light), dark: dark,
                to: directory.appendingPathComponent("profile-settings-default-\(dark ? "dark" : "light").png"))
            editor.selectEditingProfile("work")
            try PreviewExport.save(ProfileNameSheet(request: request, onConfirm: { _ in }, onCancel: {})
                .frame(width: 440).foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light), dark: dark,
                to: directory.appendingPathComponent("profile-name-sheet-\(dark ? "dark" : "light").png"))
            try PreviewExport.save(DockImportPreview(change: change, apply: {}, cancel: {})
                .frame(width: 680, height: 520).foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light), dark: dark,
                to: directory.appendingPathComponent("profile-dock-sheet-\(dark ? "dark" : "light").png"))
        }
        // Match the real default (580 pt) and minimum (540 pt) content
        // constraints, including the same outer/pane padding. Names are fake.
        let defaultID = source.defaultProfileID
        let ordinaryName = source.defaultProfile.name
        for width: CGFloat in [SettingsWindowLayout.defaultWidth, 540] {
            for longName in [false, true] {
                if let index = source.profiles.firstIndex(where: { $0.id == defaultID }) {
                    source.profiles[index].name = longName
                        ? "매우 긴 이름의 프로필 · 프로젝트와 예배 준비를 함께 정리하는 개인 구성"
                        : ordinaryName
                }
                editor.synchronize()
                editor.selectEditingProfile(defaultID)
                try PreviewExport.save(view.padding(SettingsWindowLayout.outerPadding)
                    .frame(width: width, height: 660)
                    .foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light), dark: false,
                    to: directory.appendingPathComponent("profile-settings-\(Int(width))-\(longName ? "long" : "regular").png"))
            }
        }
        editor.pause()
        print("Profile settings UI: actual settings/name/Dock views exported; production Toggle binding isolation, Save/Cancel, tab retention, immutable clone snapshot and explicit Dock apply/undo verified with synthetic defaults only; no live UI input was sent.")
    }
}
#endif
