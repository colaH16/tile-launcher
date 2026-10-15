import AppKit
import CryptoKit
import DeckCore

/// Bundle inspection runs on one utility queue, only for a new app's menu or an
/// explicit refresh. Catalogs (including misses) survive launches/app updates.
final class MenuIconRepository {
    static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TileLauncher/MenuIcons/v1", isDirectory: true)
    let root: URL
    private var catalogs: [String: [MenuIconCandidate]]
    private var titles: [String: [MenuIconCandidate]]
    init(root: URL = defaultRoot) {
        self.root = root
        catalogs = Self.read(root.appendingPathComponent("index.json"), limit: 32 * 1024 * 1024)
            .flatMap { try? JSONDecoder().decode([String: [MenuIconCandidate]].self, from: $0) } ?? [:]
        titles = Dictionary(grouping: catalogs.values.flatMap { $0 }, by: { MenuIconMatch.key($0.title) })
    }
    func resolve(_ command: MenuCommand) -> MenuResourceIcon? {
        MenuIconMatch.resolve(appID: command.appID, path: command.path, candidates: titles[MenuIconMatch.key(command.title)] ?? [])
    }
    func prepare(appID: String, name: String, url: URL?, refresh: Bool) throws {
        if !refresh, catalogs[appID] != nil { return }
        guard let url, let bundle = Bundle(url: url), let resources = bundle.resourceURL else {
            // A transient missing installation is not a successful refresh.
            throw CocoaError(.fileNoSuchFile)
        }
        let candidates = try scan(bundle: bundle, resources: resources, appID: appID, appName: name)
        var next = catalogs
        next[appID] = candidates
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(next)
        guard encoded.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        try encoded.write(to: root.appendingPathComponent("index.json"), options: .atomic)
        catalogs = next
        titles = Dictionary(grouping: catalogs.values.flatMap { $0 }, by: { MenuIconMatch.key($0.title) })
    }
    private static func read(_ url: URL, limit: Int) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Bound the actual read too, in case an updater replaces the file after stat.
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }
    private func scan(bundle: Bundle, resources: URL, appID: String, appName: String) throws -> [MenuIconCandidate] {
        let fm = FileManager.default
        let rootPath = resources.resolvingSymlinksInPath().path + "/"
        guard let walker = fm.enumerator(at: resources, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                         options: [.skipsHiddenFiles]) else { return [] }
        var nibs: [URL] = [], tables: [String: [URL]] = [:]
        var inspected = 0
        // No frameworks, plug-ins or nested apps; finite work even for large bundles.
        while let file = walker.nextObject() as? URL {
            inspected += 1
            if inspected > 12_000 { break }
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true || file.pathComponents.count > resources.pathComponents.count + 3 {
                walker.skipDescendants(); continue
            }
            if values?.isDirectory == true && ["app", "bundle", "framework"].contains(file.pathExtension) {
                walker.skipDescendants(); continue
            }
            guard file.resolvingSymlinksInPath().path.hasPrefix(rootPath) else { continue }
            if file.pathExtension == "nib", values?.isDirectory != true, nibs.count < 256 { nibs.append(file) }
            if file.pathExtension == "strings" {
                tables[file.deletingPathExtension().lastPathComponent, default: []].append(file)
            }
        }
        var result: [MenuIconCandidate] = []
        var seen = Set<MenuResourceKey>()
        var pictures: [String: MenuResourceIcon] = [:]
        var totalBytes = 0, localizationBytes = 0, imageBytes = 0
        for file in nibs.sorted(by: { $0.path < $1.path }) {
            guard let data = Self.read(file, limit: 8 * 1024 * 1024) else { continue }
            totalBytes += data.count
            if totalBytes > 32 * 1024 * 1024 { break }
            let links = MenuNibResources.links(in: data)
            guard !links.isEmpty else { continue }
            var translations: [[String: String]] = [[:]]
            for table in (tables[file.deletingPathExtension().lastPathComponent] ?? []).sorted(by: { $0.path < $1.path }).prefix(64) {
                guard localizationBytes < 8 * 1024 * 1024,
                      let bytes = Self.read(table, limit: 512 * 1024) else { continue }
                localizationBytes += bytes.count
                if let strings = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: String] {
                    translations.append(strings)
                }
            }
            for link in links.prefix(2048) {
                let resourceKey = "\(link.systemSymbol):\(link.resource)"
                let icon: MenuResourceIcon
                if let cached = pictures[resourceKey] { icon = cached }
                else {
                    guard pictures.count < 256,
                          // Resource names are bundle names, never arbitrary paths.
                          !link.resource.contains("/"), !link.resource.contains("\\"), !link.resource.contains(".."),
                          let image = link.systemSymbol
                            ? NSImage(systemSymbolName: link.resource, accessibilityDescription: nil)
                            : bundle.image(forResource: NSImage.Name(link.resource)) else { continue }
                    let kind: MenuResourceIcon.Kind, bytes: Data
                    if link.systemSymbol {
                        kind = .symbol; bytes = Data(link.resource.utf8)
                    } else if let original = Self.original(image) {
                        kind = original.0; bytes = original.1
                    } else { continue }
                    guard imageBytes + bytes.count <= 32 * 1024 * 1024 else { continue }
                    imageBytes += bytes.count
                    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                    if kind != .symbol {
                        try fm.createDirectory(at: root, withIntermediateDirectories: true)
                        let output = root.appendingPathComponent(digest + "." + kind.rawValue)
                        if !fm.fileExists(atPath: output.path) { try bytes.write(to: output, options: .atomic) }
                    }
                    icon = MenuResourceIcon(kind: kind, digest: digest, template: link.systemSymbol || image.isTemplate,
                                            sourceAppID: appID, sourceAppName: appName, resourceName: link.resource)
                    pictures[resourceKey] = icon
                }
                for strings in translations {
                    let title = link.titleKey.flatMap { strings[$0] } ?? link.title
                    let parent = link.parentKey.flatMap { strings[$0] } ?? link.parent
                    let key = MenuResourceKey(title: title, parent: parent, digest: icon.digest)
                    if result.count < 24_000 && seen.insert(key).inserted {
                        result.append(MenuIconCandidate(title: title, parent: parent, icon: icon))
                    }
                }
            }
        }
        return result
    }
    /// Never rasterize a vector. Unknown representations fall back to the
    /// existing glyph; bitmaps keep their highest available native resolution.
    static func original(_ image: NSImage) -> (MenuResourceIcon.Kind, Data)? {
        if let pdf = image.representations.compactMap({ $0 as? NSPDFImageRep }).first {
            let bytes = pdf.pdfRepresentation
            return bytes.count <= 8 * 1024 * 1024 ? (.pdf, bytes) : nil
        }
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .filter({ $0.pixelsWide > 0 && $0.pixelsHigh > 0 && $0.pixelsWide <= 4096 && $0.pixelsHigh <= 4096 })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
              let bytes = bitmap.representation(using: .png, properties: [:]), bytes.count <= 8 * 1024 * 1024 else { return nil }
        return (.png, bytes)
    }
}
private struct MenuResourceKey: Hashable { let title: String; let parent: String?; let digest: String }

/// Only immutable content-addressed images are shared by the renderer.
enum SavedMenuImages {
    // Changed only by isolated offscreen validation, before any images are read.
    static var root = MenuIconRepository.defaultRoot
    private final class Entry { let image: NSImage?; init(_ image: NSImage?) { self.image = image } }
    private static let cache = NSCache<NSString, Entry>()
    static func invalidate() { cache.removeAllObjects() }
    static func image(_ icon: MenuResourceIcon) -> NSImage? {
        guard icon.validDigest else { return nil }
        let key = (root.path + icon.kind.rawValue + icon.digest + (icon.template ? "-template" : "-color")) as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        let loaded = icon.kind == .symbol
            ? NSImage(systemSymbolName: icon.resourceName, accessibilityDescription: nil)
            : NSImage(contentsOf: root.appendingPathComponent(icon.digest + "." + icon.kind.rawValue))
        loaded?.isTemplate = icon.template
        cache.countLimit = 512
        cache.setObject(Entry(loaded), forKey: key)
        return loaded
    }
}

final class MenuIconService {
    private weak var settings: SettingsStore?
    private let queue = DispatchQueue(label: "TileLauncher.menu-icons", qos: .utility)
    // Lazy so disk I/O begins on the utility queue, not at overlay launch.
    private let root: URL
    private let applicationURL: (String) -> URL?
    private lazy var repository = MenuIconRepository(root: root)
    init(settings: SettingsStore, root: URL = MenuIconRepository.defaultRoot,
         applicationURL: @escaping (String) -> URL? = { id in
             id.hasPrefix("/") ? URL(fileURLWithPath: id) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
         }) {
        self.root = root; self.applicationURL = applicationURL
        self.settings = settings
        settings.onMenuAdded = { [weak self] command in self?.request([command], refresh: false) }
        settings.onRefreshMenuIcons = { [weak self, weak settings] appID in
            guard let settings else { return }
            self?.request(settings.commands.filter { $0.appID == appID }, refresh: true)
        }
    }
    private func request(_ commands: [MenuCommand], refresh: Bool) {
        guard let first = commands.first, let settings else { return }
        let appID = first.appID
        if refresh && settings.refreshingMenuIcons.contains(appID) { return }
        if refresh { settings.refreshingMenuIcons.insert(appID) }
        let url = applicationURL(appID)
        queue.async { [weak self] in
            guard let self else { return }
            var failure = false
            do { try self.repository.prepare(appID: appID, name: first.appName, url: url, refresh: refresh) }
            catch { failure = true }
            let failed = failure
            let resolved: [(UUID, MenuResourceIcon?)] = failed && refresh ? []
                : commands.map { ($0.id, self.repository.resolve($0)) }
            DispatchQueue.main.async { [weak self] in
                guard let settings = self?.settings else { return }
                SavedMenuImages.invalidate()
                var next = settings.commands, found = 0
                for (id, icon) in resolved {
                    guard let icon, let index = next.firstIndex(where: { $0.id == id }) else { continue }
                    next[index].resourceIcon = icon; found += 1
                }
                if next != settings.commands { settings.commands = next }
                if refresh {
                    settings.refreshingMenuIcons.remove(appID)
                    settings.menuIconStatus[appID] = failed ? "앱 리소스를 읽지 못해 저장된 아이콘을 유지했습니다."
                        : "\(found)개 아이콘 확인 · 찾지 못한 항목과 직접 지정한 아이콘은 유지합니다."
                }
            }
        }
    }
}
