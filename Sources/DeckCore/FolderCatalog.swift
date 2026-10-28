import Foundation

public struct FolderEntry: Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let directory: Bool
    public let dateAdded: Date?
}
public enum FolderSort: String, CaseIterable, Identifiable {
    case added = "추가된 날짜순", name = "이름순"
    public var id: String { rawValue }
}
public enum FolderCatalog {
    public static func read(_ url: URL) throws -> [FolderEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .localizedNameKey,
                                        .addedToDirectoryDateKey, .creationDateKey]
        return try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ).compactMap { child in
            guard let values = try? child.resourceValues(forKeys: keys) else { return nil }
            return FolderEntry(url: child, name: values.localizedName ?? child.lastPathComponent,
                               directory: values.isDirectory == true && values.isPackage != true,
                               dateAdded: values.allValues[.addedToDirectoryDateKey] as? Date ?? values.creationDate)
        }
    }
    public static func sorted(_ entries: [FolderEntry], by sort: FolderSort) -> [FolderEntry] {
        entries.sorted {
            if sort == .added {
                let left = $0.dateAdded ?? .distantPast, right = $1.dateAdded ?? .distantPast
                if left != right { return left > right }
            }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.url.path < $1.url.path : comparison == .orderedAscending
        }
    }
}
