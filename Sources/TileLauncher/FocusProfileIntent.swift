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
struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        #if TILE_LAUNCHER_PROFILE_DIAGNOSTICS
        // Counts only (requested vs resolved); same single await/filter; the
        // same error is rethrown. Invisible when no session is recording here.
        let token = ProfileDiagnosticsEntityBridge.shared.begin(requestedCount: identifiers.count)
        do {
            let result = try await suggestedEntities().filter { identifiers.contains($0.id) }
            ProfileDiagnosticsEntityBridge.shared.finish(token, resolvedCount: result.count, failed: false)
            return result
        } catch {
            ProfileDiagnosticsEntityBridge.shared.finish(token, resolvedCount: nil, failed: true)
            throw error
        }
        #else
        try await suggestedEntities().filter { identifiers.contains($0.id) }
        #endif
    }
    func suggestedEntities() async throws -> [ProfileEntity] {
        let defaults = UserDefaults.standard
        return LauncherProfile.restore(profiles: defaults.data(forKey: "launcherProfiles"),
                                       legacyPins: defaults.data(forKey: "pinnedItems"))
            .map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}
struct LauncherFocusIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "런처 프로필"
    static var description: IntentDescription? = "집중 모드에서 사용할 등록 앱·폴더 구성을 선택합니다."
    @Parameter(title: "프로필") var profile: ProfileEntity?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "런처 프로필", subtitle: "\(profile?.name ?? "기본 설정")")
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
