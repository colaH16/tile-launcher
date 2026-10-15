import Foundation

/// Candidates must be direct, actionable items of the application's own menu,
/// never document, project, services or system Apple-menu items.
public enum AppSettingsMenuMatch {
    public struct Candidate: Equatable {
        public let title: String
        public let shortcut: MenuShortcut?
        public init(title: String, shortcut: MenuShortcut?) { self.title = title; self.shortcut = shortcut }
    }
    public static func index(in candidates: [Candidate]) -> Int? {
        let standard = candidates.indices.filter {
            candidates[$0].shortcut == MenuShortcut(key: ",", modifiers: 0)
        }
        if !standard.isEmpty { return standard.count == 1 ? standard[0] : nil }
        let named = candidates.indices.filter { isSettingsTitle(candidates[$0].title) }
        return named.count == 1 ? named[0] : nil
    }
    public static func isSettingsTitle(_ title: String) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["settings", "preferences", "설정", "환경설정", "환경 설정",
                "設定", "環境設定", "设置", "偏好设置", "偏好設定"].contains(name)
    }
}
