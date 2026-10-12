import AppKit
import DeckCore

enum DockImporter {
    static func load() throws -> DockImportResult {
        // Read preferences without changing Dock or restarting it.
        let domain = "com.apple.dock" as CFString
        let rawApps = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain)
        let rawOthers = CFPreferencesCopyAppValue("persistent-others" as CFString, domain)
        guard let apps = rawApps as? [Any], rawOthers == nil || rawOthers is [Any] else {
            throw NSError(domain: "TileLauncher.DockImport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Dock의 등록 목록을 읽지 못했습니다. 앱·폴더를 직접 추가할 수 있습니다."])
        }
        let parsed = DockImport.parse(apps: apps, others: rawOthers as? [Any] ?? [])
        var items: [PinnedItem] = []
        var skipped = parsed.skipped
        if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            items.append(PinnedItem(kind: .app, path: finder.path, bundleID: "com.apple.finder", name: "Finder"))
        }
        for pin in parsed.items {
            let url = pin.url
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
                skipped += 1
                continue
            }
            items.append(PinnedItem(kind: pin.kind, path: url.path, bundleID: pin.bundleID,
                                    name: pin.name, openMode: pin.openMode))
        }
        items.append(PinnedItem(kind: .trash,
                                path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path,
                                bundleID: nil, name: "휴지통"))
        return DockImportResult(items: items, skipped: skipped)
    }
}
