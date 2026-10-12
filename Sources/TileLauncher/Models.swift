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
    let pins: [PinnedItem]
    let profileID: String
    let profileName: String
    let shortcuts: NumberShortcutAssignment
    let commands: [MenuCommand]
}
final class SettingsStore: ObservableObject {
    @Published private(set) var importingDock = false
    @Published private(set) var dockImportMessage: String?
    @Published var profiles: [LauncherProfile] { didSet { save() } }
    @Published var manualProfileID: String { didSet { save() } }
    @Published var followFocus: Bool { didSet { save() } }
    @Published var focusProfileID: String?
    @Published var numberShortcuts: NumberShortcutAssignment { didSet { save() } }
    @Published var commands: [MenuCommand] { didSet { save() } }
    var activeProfile: LauncherProfile {
        let id = followFocus ? (focusProfileID ?? manualProfileID) : manualProfileID
        return profiles.first { $0.id == id } ?? profiles[0]
    }
    var pins: [PinnedItem] {
        get { activeProfile.items }
        set { setItems(newValue, profileID: activeProfile.id) }
    }
    func setItems(_ items: [PinnedItem], profileID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].items = items
    }
    func selectProfile(_ id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        followFocus = false
        manualProfileID = id
    }
    func addProfile(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = LauncherProfile(name: name, items: pins)
        profiles.append(profile)
        selectProfile(profile.id)
    }
    func removeActiveProfile() {
        let id = activeProfile.id
        guard id != "default", profiles.count > 1 else { return }
        selectProfile(profiles.first { $0.id != id }!.id)
        profiles.removeAll { $0.id == id }
    }
    func addCommand(_ command: MenuCommand) {
        guard !commands.contains(where: { $0.appID == command.appID && $0.path == command.path }) else { return }
        commands.append(command)
    }
    func togglePin(_ id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[i].isPinned.toggle()
    }
    func recordUse(_ id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[i].useCount = min(Int.max - 1, commands[i].useCount) + 1
        commands[i].lastUsed = Date()
    }
    func moveCommand(_ id: UUID, by offset: Int) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        guard commands[i].isWide else { return }
        let peers = commands.indices.filter {
            commands[$0].appID == commands[i].appID && commands[$0].isPinned == commands[i].isPinned && commands[$0].isWide
        }
        guard let old = peers.firstIndex(of: i), peers.indices.contains(old + offset) else { return }
        commands.swapAt(i, peers[old + offset])
    }
    @Published var automatic: Bool { didSet { save() } }
    @Published var manualCount: Int { didSet { save() } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = LauncherProfile.restore(profiles: defaults.data(forKey: "launcherProfiles"),
                                           legacyPins: defaults.data(forKey: "pinnedItems"))
        manualProfileID = defaults.string(forKey: "manualProfileID") ?? "default"
        followFocus = defaults.object(forKey: "followFocus") as? Bool ?? true
        numberShortcuts = defaults.string(forKey: "numberShortcuts").flatMap(NumberShortcutAssignment.init(rawValue:)) ?? .registeredFirst
        commands = defaults.data(forKey: "menuCommands").flatMap { try? JSONDecoder().decode([MenuCommand].self, from: $0) } ?? []
        automatic = defaults.object(forKey: "automaticWindowCount") as? Bool ?? true
        manualCount = max(6, defaults.object(forKey: "manualWindowCount") as? Int ?? 12)
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "launcherProfiles") }
        if let data = try? JSONEncoder().encode(profiles.first { $0.id == "default" }?.items ?? profiles[0].items) {
            defaults.set(data, forKey: "pinnedItems")
        }
        if let data = try? JSONEncoder().encode(commands) { defaults.set(data, forKey: "menuCommands") }
        defaults.set(manualProfileID, forKey: "manualProfileID")
        defaults.set(followFocus, forKey: "followFocus")
        defaults.set(numberShortcuts.rawValue, forKey: "numberShortcuts")
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
        let targetProfileID = activeProfile.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DockImporter.load() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.importingDock = false
                switch result {
                case .success(let imported):
                    guard let target = self.profiles.first(where: { $0.id == targetProfileID }) else { return }
                    let merged = DockImport.merge(imported.items, into: target.items)
                    self.setItems(merged, profileID: targetProfileID)
                    let added = max(0, merged.count - target.items.count)
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
