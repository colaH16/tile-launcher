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
        try await suggestedEntities().filter { identifiers.contains($0.id) }
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
            NotificationCenter.default.post(name: .launcherFocusChanged, object: nil,
                                             userInfo: ["profileID": id as Any])
        }
        return .result()
    }
}
extension Notification.Name {
    static let launcherFocusChanged = Notification.Name("TileLauncher.focusChanged")
}
