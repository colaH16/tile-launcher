import Foundation

enum AppIdentity {
    static let name = "Tile Launcher"
    static let bundleID = Bundle.main.bundleIdentifier ?? "dev.cola16.TileLauncher"
    // Read once from the running bundle; an in-place update must not relabel an old process.
    static let versionLabel: String = {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return "소스 미리보기"
        }
        return "버전 \(version) · 빌드 \(build)"
    }()
}
