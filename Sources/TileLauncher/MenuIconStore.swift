import AppKit
import CryptoKit
import DeckCore

/// Bundle inspection runs on one utility queue, only for a new app's menu or an
/// explicit refresh. One file per app (R191) so refreshing an app rewrites only
/// that app and one large app cannot block others. Catalogs (including misses)
/// survive launches/app updates. Only selected languages are stored.
final class MenuIconRepository {
    static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TileLauncher/MenuIcons/v2", isDirectory: true)
    private struct AppCatalog: Codable {
        let appID: String
        let candidates: [MenuIconCandidate]
        /// Normalized title → that item's names in the stored languages.
        let aliases: [String: [String]]
        let localizations: [String]
    }
    private static let fileLimit = 8 * 1024 * 1024
    let root: URL
    private let preferredLanguages: [String]
    private var catalogs: [String: AppCatalog] = [:]
    private var titles: [String: [MenuIconCandidate]] = [:]
    init(root: URL = defaultRoot, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.root = root
        self.preferredLanguages = preferredLanguages
        let directory = root.appendingPathComponent("apps", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "json" }).prefix(1024) {
            guard let data = Self.read(file, limit: Self.fileLimit),
                  let catalog = try? JSONDecoder().decode(AppCatalog.self, from: data) else { continue }
            catalogs[catalog.appID] = catalog
        }
        rebuildTitles()
    }
    private func rebuildTitles() {
        titles = Dictionary(grouping: catalogs.values.flatMap(\.candidates), by: { MenuIconMatch.key($0.title) })
    }
    private func file(for appID: String) -> URL {
        let name = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("apps/\(name).json")
    }
    func resolve(_ command: MenuCommand) -> MenuResourceIcon? {
        MenuIconMatch.resolve(appID: command.appID, path: command.path, candidates: titles[MenuIconMatch.key(command.title)] ?? [])
    }
    func aliases(for command: MenuCommand) -> [[String]]? {
        catalogs[command.appID].flatMap { MenuAliasIndex.aliases(for: command.path, in: $0.aliases) }
    }
    func localizations(appID: String) -> [String]? { catalogs[appID]?.localizations }
    /// `capturedTitles` are this app's saved menu names; a localization that
    /// contains one of them is kept even if it is not a macOS preferred language.
    func prepare(appID: String, name: String, url: URL?, refresh: Bool, capturedTitles: [String] = []) throws {
        if !refresh, catalogs[appID] != nil { return }
        guard let url, let bundle = Bundle(url: url), let resources = bundle.resourceURL else {
            // A transient missing installation is not a successful refresh.
            throw CocoaError(.fileNoSuchFile)
        }
        let catalog = try scan(bundle: bundle, resources: resources, appID: appID, appName: name,
                               capturedTitles: Set(capturedTitles.map(MenuIconMatch.key)))
        let encoded = try JSONEncoder().encode(catalog)
        guard encoded.count <= Self.fileLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        let output = file(for: appID)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: output, options: .atomic)
        catalogs[appID] = catalog
        rebuildTitles()
    }
    private static func read(_ url: URL, limit: Int) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Bound the actual read too, in case an updater replaces the file after stat.
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }
    /// A compiled `Name.nib` may be a folder of per-OS archives
    /// (`keyedobjects.nib`, `keyedobjects-110000.nib`, `designable.nib`).
    /// Use the newest runtime archive and the folder's name for its .strings.
    static func nibs(_ files: [URL]) -> [(name: String, url: URL)] {
        var single: [(String, URL)] = []
        var folders: [URL: (rank: Int, url: URL)] = [:]
        for file in files {
            let folder = file.deletingLastPathComponent()
            guard folder.pathExtension == "nib" else {
                single.append((file.deletingPathExtension().lastPathComponent, file)); continue
            }
            let base = file.deletingPathExtension().lastPathComponent
            let rank: Int
            if base == "keyedobjects" { rank = 0 }
            else if base.hasPrefix("keyedobjects-"), let number = Int(base.dropFirst("keyedobjects-".count)) { rank = number }
            else { continue } // designable.nib is Interface Builder data, not the runtime menu
            if (folders[folder]?.rank ?? -1) < rank { folders[folder] = (rank, file) }
        }
        let grouped = folders.map { ($0.key.deletingPathExtension().lastPathComponent, $0.value.url) }
        return (single + grouped).sorted { $0.1.path < $1.1.path }
    }
    private func scan(bundle: Bundle, resources: URL, appID: String, appName: String,
                      capturedTitles: Set<String>) throws -> AppCatalog {
        let fm = FileManager.default
        let rootPath = resources.resolvingSymlinksInPath().path + "/"
        guard let walker = fm.enumerator(at: resources, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                         options: [.skipsHiddenFiles]) else {
            return AppCatalog(appID: appID, candidates: [], aliases: [:], localizations: [])
        }
        var nibFiles: [URL] = []
        // nib name → [(localization, file)]
        var tables: [String: [(String, URL)]] = [:]
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
            if file.pathExtension == "nib", values?.isDirectory != true, nibFiles.count < 512 { nibFiles.append(file) }
            let folder = file.deletingLastPathComponent()
            if file.pathExtension == "strings", folder.pathExtension == "lproj" {
                tables[file.deletingPathExtension().lastPathComponent, default: []]
                    .append((folder.deletingPathExtension().lastPathComponent, file))
            }
        }
        // Parse every menu archive once, and read its translations for all languages.
        var parsed: [(links: [MenuNibResources.Link], items: [MenuNibResources.Item], strings: [String: [String: String]])] = []
        var totalBytes = 0, localizationBytes = 0
        for (name, file) in Self.nibs(nibFiles).prefix(256) {
            guard let data = Self.read(file, limit: 8 * 1024 * 1024) else { continue }
            totalBytes += data.count
            if totalBytes > 32 * 1024 * 1024 { break }
            let contents = MenuNibResources.contents(in: data)
            guard !contents.items.isEmpty else { continue }
            var strings: [String: [String: String]] = [:]
            for (language, table) in (tables[name] ?? []).sorted(by: { $0.1.path < $1.1.path }).prefix(96) {
                guard localizationBytes < 16 * 1024 * 1024, let bytes = Self.read(table, limit: 512 * 1024) else { continue }
                localizationBytes += bytes.count
                if let values = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: String] {
                    strings[language, default: [:]].merge(values) { first, _ in first }
                }
            }
            parsed.append((contents.links, contents.items, strings))
        }
        // Keep macOS preferred languages, US English, the development language and
        // any language the user's captured menus of this app are written in.
        let captured = Set(parsed.flatMap { nib in
            nib.strings.filter { $0.value.values.contains { capturedTitles.contains(MenuIconMatch.key($0)) } }.map(\.key)
        })
        let selected = MenuLanguageSelection.select(available: bundle.localizations, preferred: preferredLanguages,
                                                    development: bundle.developmentLocalization, capturedIn: captured)
        var result: [MenuIconCandidate] = []
        var aliases: [String: Set<String>] = [:]
        var seen = Set<MenuResourceKey>()
        var pictures: [String: MenuResourceIcon] = [:]
        var imageBytes = 0
        for nib in parsed {
            let translations: [[String: String]] = [[:]] + nib.strings.filter { selected.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
            for (key, names) in MenuAliasIndex.build(items: nib.items.map { ($0.title, $0.titleKey) }, tables: translations)
            where aliases[key] != nil || aliases.count < 20_000 {
                aliases[key, default: []].formUnion(names)
            }
            for link in nib.links.prefix(2048) {
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
        return AppCatalog(appID: appID, candidates: result, aliases: aliases.mapValues { $0.sorted() },
                          localizations: selected.sorted())
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
    private let preferredLanguages: [String]
    private let applicationURL: (String) -> URL?
    private lazy var repository = MenuIconRepository(root: root, preferredLanguages: preferredLanguages)
    init(settings: SettingsStore, root: URL = MenuIconRepository.defaultRoot,
         preferredLanguages: [String] = Locale.preferredLanguages,
         applicationURL: @escaping (String) -> URL? = { id in
             id.hasPrefix("/") ? URL(fileURLWithPath: id) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
         }) {
        self.root = root; self.preferredLanguages = preferredLanguages; self.applicationURL = applicationURL
        self.settings = settings
        settings.onMenuAdded = { [weak self] command in self?.request([command], refresh: false) }
        settings.onRefreshMenuIcons = { [weak self, weak settings] appID in
            guard let settings else { return }
            self?.request(settings.commands.filter { $0.appID == appID }, refresh: true)
        }
        // Menus saved before language aliases existed: read each app once in the
        // background. Later launches only resolve from the saved catalog.
        let missing = Dictionary(grouping: settings.commands.filter { $0.pathAliases == nil }, by: \.appID)
        for commands in missing.values.sorted(by: { $0[0].appID < $1[0].appID }) { request(commands, refresh: false) }
    }
    private func request(_ commands: [MenuCommand], refresh: Bool) {
        guard let first = commands.first, let settings else { return }
        let appID = first.appID
        if refresh && settings.refreshingMenuIcons.contains(appID) { return }
        if refresh { settings.refreshingMenuIcons.insert(appID) }
        let url = applicationURL(appID)
        // Every name the user's menus of this app are saved with, so a language
        // the app runs in is kept even if macOS does not prefer it.
        let captured = settings.commands.filter { $0.appID == appID }.flatMap(\.path)
        queue.async { [weak self] in
            guard let self else { return }
            var failure = false
            do {
                try self.repository.prepare(appID: appID, name: first.appName, url: url, refresh: refresh,
                                            capturedTitles: captured)
            } catch { failure = true }
            let failed = failure
            let resolved: [(UUID, MenuResourceIcon?, [[String]]?)] = failed && refresh ? []
                : commands.map { ($0.id, self.repository.resolve($0), self.repository.aliases(for: $0)) }
            let languages = self.repository.localizations(appID: appID) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let settings = self?.settings else { return }
                SavedMenuImages.invalidate()
                var next = settings.commands, found = 0
                for (id, icon, aliases) in resolved {
                    guard let index = next.firstIndex(where: { $0.id == id }) else { continue }
                    if let icon { next[index].resourceIcon = icon; found += 1 }
                    // An empty list records “checked”; nil means not read yet.
                    if let aliases { next[index].pathAliases = aliases }
                    else if !failed && next[index].pathAliases == nil { next[index].pathAliases = [] }
                }
                if next != settings.commands { settings.commands = next }
                if refresh {
                    settings.refreshingMenuIcons.remove(appID)
                    settings.menuIconStatus[appID] = failed ? "앱 리소스를 읽지 못해 저장된 아이콘을 유지했습니다."
                        : "\(found)개 아이콘 확인 · 저장한 언어: \(languages.joined(separator: ", ")) · 찾지 못한 항목과 직접 지정한 아이콘은 유지합니다."
                }
            }
        }
    }
}
