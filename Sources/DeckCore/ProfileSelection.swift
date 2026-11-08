import Foundation

/// Persisted profile roles, restored without creating a SettingsStore or writing
/// defaults. App Intent queries use this same read-only catalog as the app.
public struct ProfileCatalog: Equatable {
    public let profiles: [LauncherProfile]
    public let defaultProfileID: String
    public let manualProfileID: String

    public static func restore(profilesData: Data?, legacyPinsData: Data?, storedDefaultID: String?,
                               storedManualID: String?) -> Self {
        var profiles = LauncherProfile.restore(profiles: profilesData, legacyPins: legacyPinsData)
        let fallback = profiles.first(where: { $0.id == storedManualID }) ?? profiles[0]
        let defaultID: String
        if let storedDefaultID, profiles.contains(where: { $0.id == storedDefaultID }) {
            defaultID = storedDefaultID
        } else if profiles.contains(where: { $0.id == "default" }) {
            defaultID = "default"
        } else {
            // Preserve every old identity, reference, item and relative order.
            // The new role copies the former fallback rather than taking an
            // existing Focus profile (often the user's Work profile) out of use.
            profiles.append(LauncherProfile(id: "default", name: "기본", items: fallback.items))
            defaultID = "default"
        }
        let manualID = storedManualID.flatMap { id in profiles.contains(where: { $0.id == id }) ? id : nil } ?? defaultID
        return Self(profiles: profiles, defaultProfileID: defaultID, manualProfileID: manualID)
    }
}

/// One selection contract for the app, Focus boundaries, icon prewarming and
/// diagnostics. The settings editor's navigation target is deliberately absent.
public enum ProfileSelection {
    public enum Reason: Equatable { case focus, manual, defaultProfile }
    public struct Decision: Equatable {
        public let profile: LauncherProfile
        public let reason: Reason
    }
    public struct Selection: Equatable {
        public let profileID: String
        public let reason: Reason
    }
    public static func isEligibleForFocus(_ id: String?, profiles: [LauncherProfile], defaultProfileID: String) -> Bool {
        isEligibleForFocus(id, profileIDs: profiles.map(\.id), defaultProfileID: defaultProfileID)
    }
    public static func isEligibleForFocus(_ id: String?, profileIDs: [String], defaultProfileID: String) -> Bool {
        let effectiveDefault = profileIDs.contains(defaultProfileID) ? defaultProfileID : profileIDs.first
        guard let id, id != effectiveDefault else { return false }
        return profileIDs.contains(id)
    }
    public static func focusID(_ id: String?, profiles: [LauncherProfile], defaultProfileID: String) -> String? {
        isEligibleForFocus(id, profiles: profiles, defaultProfileID: defaultProfileID) ? id : nil
    }
    public static func normalizedFocusID(_ id: String?, profiles: [LauncherProfile], defaultProfileID: String) -> String? {
        focusID(id, profiles: profiles, defaultProfileID: defaultProfileID)
    }
    public static func resolve(profiles: [LauncherProfile], defaultProfileID: String, manualProfileID: String,
                               focusProfileID: String?, followFocus: Bool) -> Decision? {
        guard let chosen = selection(profileIDs: profiles.map(\.id), defaultProfileID: defaultProfileID,
                                     manualProfileID: manualProfileID, focusProfileID: focusProfileID, followFocus: followFocus),
              let profile = profiles.first(where: { $0.id == chosen.profileID }) else { return nil }
        return Decision(profile: profile, reason: chosen.reason)
    }
    public static func selection(profileIDs: [String], defaultProfileID: String, manualProfileID: String,
                                 focusProfileID: String?, followFocus: Bool) -> Selection? {
        guard let fallback = profileIDs.contains(defaultProfileID) ? defaultProfileID : profileIDs.first else { return nil }
        if followFocus {
            if let focusProfileID, isEligibleForFocus(focusProfileID, profileIDs: profileIDs, defaultProfileID: fallback) {
                return Selection(profileID: focusProfileID, reason: .focus)
            }
            return Selection(profileID: fallback, reason: .defaultProfile)
        }
        if profileIDs.contains(manualProfileID) {
            return Selection(profileID: manualProfileID, reason: .manual)
        }
        return Selection(profileID: fallback, reason: .defaultProfile)
    }
}
