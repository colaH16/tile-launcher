import AppIntents
import Foundation
import DeckCore

struct ProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "런처 프로필"
    static var defaultQuery = ProfileQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// A read-only view of saved roles. App Intent resolution must not initialize a
/// SettingsStore: its initializer persists settings, and an editor's unsaved
/// default role must never change system suggestions or Focus eligibility.
struct FocusProfileCatalog {
    let saved: ProfileCatalog

    init(defaults: UserDefaults = .standard) {
        saved = ProfileCatalog.restore(profilesData: defaults.data(forKey: "launcherProfiles"),
                                       legacyPinsData: defaults.data(forKey: "pinnedItems"),
                                       storedDefaultID: defaults.string(forKey: "defaultProfileID"),
                                       storedManualID: defaults.string(forKey: "manualProfileID"))
    }
    /// Existing OS references remain resolvable, including a profile that has
    /// since become the default. This does not authorize applying it as Focus.
    func entities(for identifiers: [String]) -> [ProfileEntity] {
        saved.profiles.filter { identifiers.contains($0.id) }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }
    var suggestions: [ProfileEntity] {
        saved.profiles.filter {
            ProfileSelection.isEligibleForFocus($0.id, profiles: saved.profiles, defaultProfileID: saved.defaultProfileID)
        }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }
    func focusID(_ id: String?) -> String? {
        ProfileSelection.focusID(id, profiles: saved.profiles, defaultProfileID: saved.defaultProfileID)
    }
}

extension SettingsStore {
    /// Preserve the framework observation in RAM. Selection, icon prewarming
    /// and diagnostics independently use the same role eligibility policy.
    /// Discarding an ineligible ID here would prevent re-evaluation if that
    /// profile later stops being the default while the OS Focus stays active.
    func recordFocusObservation(_ id: String?) { focusProfileID = id }
}

struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        #if TILE_LAUNCHER_PROFILE_DIAGNOSTICS
        // Counts only (requested vs resolved); same single await/filter; the
        // same error is rethrown. Invisible when no session is recording here.
        let token = ProfileDiagnosticsEntityBridge.shared.begin(requestedCount: identifiers.count)
        do {
            let result = try await resolvedEntities(for: identifiers)
            ProfileDiagnosticsEntityBridge.shared.finish(token, resolvedCount: result.count, failed: false)
            return result
        } catch {
            ProfileDiagnosticsEntityBridge.shared.finish(token, resolvedCount: nil, failed: true)
            throw error
        }
        #else
        try await resolvedEntities(for: identifiers)
        #endif
    }
    private func resolvedEntities(for identifiers: [String]) async throws -> [ProfileEntity] {
        FocusProfileCatalog().entities(for: identifiers)
    }
    func suggestedEntities() async throws -> [ProfileEntity] {
        FocusProfileCatalog().suggestions
    }
}
struct LauncherFocusIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "런처 프로필"
    static var description: IntentDescription? = "집중 모드에서 사용할 등록 앱·폴더 구성을 선택합니다."
    @Parameter(title: "프로필") var profile: ProfileEntity?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "런처 프로필", subtitle: "\(profile?.name ?? "프로필 연결 없음")")
    }
    func perform() async throws -> some IntentResult {
        let id = profile?.id
        await MainActor.run {
            #if TILE_LAUNCHER_PROFILE_DIAGNOSTICS
            // Process-local: a perform in another process is not observed here.
            ProfileDiagnosticsRecorder.shared.noteFocusPerform(hasProfile: id != nil)
            #endif
            NotificationCenter.default.post(name: .launcherFocusChanged, object: nil,
                                             userInfo: ["profileID": id as Any])
        }
        return .result()
    }
}
extension Notification.Name {
    static let launcherFocusChanged = Notification.Name("TileLauncher.focusChanged")
}
