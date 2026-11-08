#if TILE_LAUNCHER_DIAGNOSTICS
import DeckCore
import Foundation

/// The real App Intent catalog and application normalization helper, using a
/// private defaults suite. Never calls perform/current or posts notifications.
enum FocusProfilePolicyValidation {
    @MainActor static func verify() throws {
        try ProfileSelectionValidation.verify()
        let suite = "TileLauncher.FocusPolicyValidation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "TileLauncher.FocusProfilePolicyValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func savedDomain() -> NSDictionary {
            NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:])
        }
        let item = PinnedItem(kind: .folder, path: "/Synthetic/FocusPolicy", bundleID: nil, name: "Fixture")
        // Deliberately misleading names: eligibility follows role/ID, not text.
        let basic = LauncherProfile(id: "default", name: "Work")
        let work = LauncherProfile(id: "work", name: "기본", items: [item])
        defaults.set(try JSONEncoder().encode([basic, work]), forKey: "launcherProfiles")
        defaults.set("default", forKey: "defaultProfileID")
        defaults.set("work", forKey: "manualProfileID")
        defaults.set(true, forKey: "followFocus")
        let original = savedDomain()
        let catalog = FocusProfileCatalog(defaults: defaults)
        try check(catalog.suggestions.map(\.id) == ["work"], "New suggestions exclude only the saved default role")
        try check(catalog.entities(for: ["default", "work", "deleted"]).map(\.id) == ["default", "work"],
                  "Existing system references remain resolvable, including the default")
        try check(catalog.focusID("default") == nil && catalog.focusID("deleted") == nil
                  && catalog.focusID(nil) == nil && catalog.focusID("work") == "work",
                  "Application eligibility must reject default/missing references without blocking valid Focus")
        try check(savedDomain() == original, "Read-only App Intent resolution must never save or migrate defaults")

        // A cached entity is still displayable/editable after its role changes,
        // but re-reading the saved catalog must stop its Focus application.
        let cached = catalog.entities(for: ["work"]).first!
        defaults.set("work", forKey: "defaultProfileID")
        let changed = FocusProfileCatalog(defaults: defaults)
        try check(changed.entities(for: [cached.id]).first?.id == cached.id
                  && changed.focusID(cached.id) == nil && changed.suggestions.map(\.id) == ["default"],
                  "A newly default cached entity cannot override Focus; the former default becomes eligible")

        // Exercise the exact RAM observation boundary used by notification and
        // current. Role changes re-evaluate that same observation without an
        // additional OS read; a nil observation clears it explicitly.
        let settings = SettingsStore(defaults: defaults)
        func reason() -> ProfileSelection.Reason? {
            ProfileSelection.resolve(profiles: settings.profiles, defaultProfileID: settings.defaultProfileID,
                                     manualProfileID: settings.manualProfileID, focusProfileID: settings.focusProfileID,
                                     followFocus: settings.followFocus)?.reason
        }
        settings.recordFocusObservation("work")
        try check(settings.focusProfileID == "work" && reason() == .defaultProfile,
                  "An ineligible default observation stays in RAM but cannot select through Focus")
        settings.defaultProfileID = "default"
        try check(settings.focusProfileID == "work" && settings.activeProfile.id == "work" && reason() == .focus,
                  "An existing OS binding becomes eligible again after the default role changes, without another read")
        settings.defaultProfileID = "work"
        settings.recordFocusObservation("work")
        try check(settings.focusProfileID == "work" && reason() == .defaultProfile,
                  "A late result that became default while awaiting must not override selection")
        settings.defaultProfileID = "default"
        settings.recordFocusObservation(nil)
        try check(settings.focusProfileID == nil && settings.activeProfile.id == "default" && reason() == .defaultProfile,
                  "A nil observation uses the explicit default, not the remembered manual profile")
        let draft = settings.makeEditingCopy()
        draft.defaultProfileID = "work"
        let committed = FocusProfileCatalog(defaults: defaults)
        try check(committed.saved.defaultProfileID == "default"
                  && committed.suggestions.map(\.id) == ["work"],
                  "An unsaved draft role must not change system candidates")

        defaults.set(try JSONEncoder().encode([basic]), forKey: "launcherProfiles")
        defaults.set("default", forKey: "defaultProfileID")
        try check(FocusProfileCatalog(defaults: defaults).suggestions.isEmpty,
                  "A default-only catalog has no selectable Focus candidate")

        // Legacy catalog without the canonical role: restore a derived clone
        // without stealing an existing Focus identity or writing the catalog.
        defaults.set(try JSONEncoder().encode([work]), forKey: "launcherProfiles")
        defaults.removeObject(forKey: "defaultProfileID")
        defaults.set("work", forKey: "manualProfileID")
        let legacyBefore = savedDomain()
        let legacy = FocusProfileCatalog(defaults: defaults)
        try check(legacy.saved.profiles.map(\.id) == ["work", "default"]
                  && legacy.saved.profiles.last?.items == work.items
                  && legacy.suggestions.map(\.id) == ["work"]
                  && savedDomain() == legacyBefore,
                  "Legacy read-only restoration preserves old IDs/items and performs no write")
        print("Focus profile policy: saved-role suggestions, legacy references, raw observation/default-role flips, late-result eligibility and unsaved-draft isolation passed without OS Focus queries.")
    }
}
#endif
