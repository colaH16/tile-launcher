import AppKit
import SwiftUI
import DeckCore

struct AppItem: Identifiable {
    let id: String
    let pid: pid_t
    let name: String
    let url: URL?
}
struct WindowItem: Identifiable {
    let id: UUID
    let pid: pid_t
    let appName: String
    let appURL: URL?
    let title: String
    let minimized: Bool
}
extension PinnedItem {
    var url: URL {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? URL(fileURLWithPath: path)
    }
}
struct OverlaySnapshot {
    let context: AppItem?
    let contextWindowTitle: String?
    let apps: [AppItem]
    let windows: [WindowItem]
    let layout: PanelLayout
    let permission: Bool
}
final class SettingsStore: ObservableObject {
    @Published private(set) var importingDock = false
    @Published private(set) var dockImportMessage: String?
    @Published var pins: [PinnedItem] { didSet { save() } }
    @Published var automatic: Bool { didSet { save() } }
    @Published var manualCount: Int { didSet { save() } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pins = defaults.data(forKey: "pinnedItems")
            .flatMap { try? JSONDecoder().decode([PinnedItem].self, from: $0) } ?? []
        automatic = defaults.object(forKey: "automaticWindowCount") as? Bool ?? true
        manualCount = max(6, defaults.object(forKey: "manualWindowCount") as? Int ?? 12)
    }
    private func save() {
        if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: "pinnedItems") }
        defaults.set(automatic, forKey: "automaticWindowCount")
        defaults.set(manualCount, forKey: "manualWindowCount")
    }
    func addApplications() {
        let panel = NSOpenPanel()
        panel.title = "등록할 앱 선택"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !pins.contains(where: { $0.path == url.path }) {
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            pins.append(PinnedItem(kind: .app, path: url.path, bundleID: bundle?.bundleIdentifier, name: name))
        }
    }
    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "등록할 폴더 선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addFolderURL(url) }
    }
    func addFolderURL(_ url: URL, kind: PinnedItem.Kind = .folder, name: String? = nil) {
        guard !pins.contains(where: { $0.path == url.path }) else { return }
        pins.append(PinnedItem(kind: kind, path: url.path, bundleID: nil,
                               name: name ?? url.lastPathComponent))
    }
    func move(_ pin: PinnedItem, by offset: Int) {
        guard let old = pins.firstIndex(of: pin) else { return }
        let new = old + offset
        guard pins.indices.contains(new) else { return }
        pins.swapAt(old, new)
    }
    func setOpenMode(_ mode: FolderOpenMode, for id: PinnedItem.ID) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].setOpenMode(mode)
    }
    func importDock() {
        guard !importingDock else { return }
        importingDock = true
        dockImportMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DockImporter.load() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.importingDock = false
                switch result {
                case .success(let imported):
                    let previousCount = self.pins.count
                    self.pins = DockImport.merge(imported.items, into: self.pins)
                    let added = max(0, self.pins.count - previousCount)
                    self.dockImportMessage = "\(added)개 추가 · Dock 순서로 정리했습니다."
                        + (imported.skipped > 0 ? " 사용할 수 없거나 지원하지 않는 항목 \(imported.skipped)개는 건너뛰었습니다." : "")
                case .failure(let error): self.dockImportMessage = error.localizedDescription
                }
            }
        }
    }
}

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 96 }
    func icon(_ url: URL?) -> NSImage {
        guard let url else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        let original = NSWorkspace.shared.icon(forFile: url.path)
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        original.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        image.unlockFocus()
        cache.setObject(image, forKey: key)
        return image
    }
}
