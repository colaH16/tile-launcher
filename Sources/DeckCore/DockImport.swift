import Foundation

public struct DockImportResult {
    public let items: [PinnedItem]
    public let skipped: Int
    public init(items: [PinnedItem], skipped: Int) {
        self.items = items
        self.skipped = skipped
    }
}

/// Dock's stored tile schema is not a public API. Keep parsing isolated and
/// reject unknown data rather than inventing or launching a target.
public enum DockImport {
    public static func parse(apps: [Any], others: [Any]) -> DockImportResult {
        var items: [PinnedItem] = []
        var skipped = 0
        for value in apps + others {
            guard let tile = value as? [String: Any], let type = tile["tile-type"] as? String else {
                skipped += 1
                continue
            }
            if type == "spacer-tile" || type == "small-spacer-tile" { continue }
            guard type == "file-tile" || type == "directory-tile",
                  let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let url = fileURL(file) else {
                skipped += 1
                continue
            }
            let isApp = url.pathExtension.lowercased() == "app"
            guard isApp || type == "directory-tile" else {
                skipped += 1
                continue
            }
            let label = (data["file-label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(PinnedItem(kind: isApp ? .app : .folder, path: url.path,
                                    bundleID: isApp ? data["bundle-identifier"] as? String : nil,
                                    name: label.flatMap { $0.isEmpty ? nil : $0 }
                                        ?? (isApp ? url.deletingPathExtension() : url).lastPathComponent))
        }
        return DockImportResult(items: items, skipped: skipped)
    }

    private static func fileURL(_ data: [String: Any]) -> URL? {
        guard let value = data["_CFURLString"] as? String,
              let type = data["_CFURLStringType"] as? Int else { return nil }
        let url: URL?
        switch type {
        case 0: url = value.hasPrefix("/") ? URL(fileURLWithPath: value) : nil
        case 15: url = URL(string: value)
        default: return nil
        }
        guard let url, url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), !url.path.contains("\0") else { return nil }
        return url.standardizedFileURL
    }

    /// Dock order comes first. Preserve existing names/modes and append all
    /// non-Dock pins unchanged. Reimporting the same Dock is idempotent.
    public static func merge(_ imported: [PinnedItem], into existing: [PinnedItem]) -> [PinnedItem] {
        func same(_ lhs: PinnedItem, _ rhs: PinnedItem) -> Bool {
            if lhs.kind == .trash && rhs.kind == .trash { return true }
            if lhs.kind == .app, rhs.kind == .app,
               let id = lhs.bundleID, !id.isEmpty, id == rhs.bundleID { return true }
            return URL(fileURLWithPath: lhs.path).standardizedFileURL.path.precomposedStringWithCanonicalMapping
                == URL(fileURLWithPath: rhs.path).standardizedFileURL.path.precomposedStringWithCanonicalMapping
        }
        var result: [PinnedItem] = []
        for pin in imported {
            let preserved = existing.first { same($0, pin) } ?? pin
            if !result.contains(where: { same($0, preserved) }) { result.append(preserved) }
        }
        for pin in existing where !result.contains(where: { same($0, pin) }) { result.append(pin) }
        return result
    }
}
