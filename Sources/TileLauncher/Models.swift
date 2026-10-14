import AppKit
import SwiftUI
import DeckCore

struct AppItem: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let name: String
    let url: URL?
}
enum RecentAppearance {
    case original, squares, mixedNeutral, consecutiveSmall
    var uniform: Bool { self == .squares || self == .consecutiveSmall }
    var neutralApplications: Bool { self != .original }
}
/// Comparison-only menu variants. The shipped view retains .original until chosen.
enum MenuAppearance {
    case original, recentPastel, recentGraySquare
}
struct WindowItem: Identifiable, Equatable {
    let id: UUID
    let pid: pid_t
    let appName: String
    let appURL: URL?
    let title: String
    let minimized: Bool
    var windowID: CGWindowID? = nil
    var desktop: WindowDesktop = .unknown
    var isApplication = false
    var runningApplication: NSRunningApplication? = nil
}
extension PinnedItem {
    var url: URL {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? URL(fileURLWithPath: path)
    }
}
extension MenuCommand {
    var usageDescription: String {
        "누적 \(totalUseCount)회 · 메뉴 막대 \(observedCount)회 · Tile Launcher \(useCount)회"
    }
}
struct OverlaySnapshot: Equatable {
    let context: AppItem?
    let contextWindowTitle: String?
    let apps: [AppItem]
    let windows: [WindowItem]
    var layout: PanelLayout
    let permission: Bool
    let pins: [PinnedItem]
    let profileID: String
    let profileName: String
    let shortcuts: NumberShortcutAssignment
    let commands: [MenuCommand]
    var frequentMenuIDs: Set<UUID> = []
}
final class OverlayContent: ObservableObject {
    @Published var snapshot: OverlaySnapshot
    init(_ snapshot: OverlaySnapshot) { self.snapshot = snapshot }
    func refresh(context: AppItem?, apps: [AppItem], windows: [WindowItem],
                 trusted: Bool, commands: [MenuCommand], manualCount: Int?,
                 menuHistory: MenuHistoryPreferences = .init(), now: Date = Date()) {
        let old = snapshot
        let count = old.layout.windowLimit(manual: manualCount, actual: windows.count)
        let next = OverlaySnapshot(context: context,
                                   contextWindowTitle: windows.first { $0.pid == context?.pid && !$0.isApplication }?.title,
                                   apps: Array(apps.prefix(3)), windows: Array(windows.prefix(count)),
                                   layout: old.layout, permission: trusted, pins: old.pins,
                                   profileID: old.profileID, profileName: old.profileName, shortcuts: old.shortcuts,
                                   commands: MenuCommand.ordered(commands, appID: context?.id ?? "", history: menuHistory, at: now),
                                   frequentMenuIDs: MenuCommand.frequentIDs(commands, appID: context?.id ?? "", history: menuHistory, at: now))
        if next != old { snapshot = next }
    }
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
    @Published var menuHistory: MenuHistoryPreferences { didSet { save() } }
    @Published var menuCapture: MenuCapturePreferences { didSet { save() } }
    @Published var menuCaptureStatus: [String: String] = [:]
    var activeProfile: LauncherProfile {
        if followFocus, let focused = profiles.first(where: { $0.id == focusProfileID }) { return focused }
        // A filter can still reference a profile the user deleted or no longer has. Fall back to the user's manual choice first.
        return profiles.first { $0.id == manualProfileID } ?? profiles[0]
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
    func addProfile(name: String, copyingCurrent: Bool) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = LauncherProfile(name: name, items: copyingCurrent ? pins : [])
        profiles.append(profile)
        selectProfile(profile.id)
    }
    func removeActiveProfile() {
        let id = activeProfile.id
        guard id != "default", profiles.count > 1 else { return }
        selectProfile(profiles.first { $0.id != id }!.id)
        profiles.removeAll { $0.id == id }
    }
    func moveProfile(_ id: String, by offset: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              profiles.indices.contains(index + offset) else { return }
        profiles.swapAt(index, index + offset)
    }
    func addCommand(_ command: MenuCommand) {
        menuCapture.excludedMenus.remove(MenuIdentity(appID: command.appID, path: command.path))
        guard !commands.contains(where: { $0.appID == command.appID && $0.path == command.path }) else { return }
        commands.append(command)
    }
    func recordCapturedMenu(_ menu: CapturedMenu) {
        guard MenuCapturePolicy.allows(menu, preferences: menuCapture) else { return }
        commands = MenuCaptureHistory.record(menu, in: commands, at: Date())
    }
    func removeCommand(_ command: MenuCommand) {
        menuCapture.excludedMenus.insert(MenuIdentity(appID: command.appID, path: command.path))
        commands.removeAll { $0.id == command.id }
    }
    func clearCapturedMenus(appID: String) {
        commands.removeAll { $0.appID == appID && $0.isAutomatic && !$0.isPinned }
    }
    func togglePin(_ id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[i].isPinned.toggle()
    }
    func recordUse(_ id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[i].recordUse(at: Date())
    }
    func moveCommand(_ id: UUID, by offset: Int) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        guard commands[i].isWide(history: menuHistory, at: now) else { return }
        let peers = commands.indices.filter {
            commands[$0].appID == commands[i].appID && commands[$0].isPinned == commands[i].isPinned && commands[$0].isWide(history: menuHistory, at: now)
        }
        guard let old = peers.firstIndex(of: i), peers.indices.contains(old + offset) else { return }
        commands.swapAt(i, peers[old + offset])
    }
    @Published var automatic: Bool { didSet { save() } }
    @Published var optionTriggerEnabled: Bool { didSet { save() } }
    @Published var optionReopen: OptionReopenPreferences { didSet { save() } }
    @Published var theme: DeckTheme { didSet { save() } }
    @Published var tileColors: TileColors { didSet { save() } }
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
        menuHistory = MenuHistoryPreferences.restore(defaults.data(forKey: "menuHistoryPreferences"))
        menuCapture = MenuCapturePreferences.restore(defaults.data(forKey: "menuCapturePreferences"))
        automatic = defaults.object(forKey: "automaticWindowCount") as? Bool ?? true
        optionTriggerEnabled = defaults.object(forKey: "optionTriggerEnabled") as? Bool ?? true
        optionReopen = OptionReopenPreferences.restore(defaults.data(forKey: "optionReopenPreferences"))
        theme = defaults.string(forKey: "appearanceTheme").flatMap(DeckTheme.init(rawValue:))
            ?? .glass
        tileColors = TileColors.restore(defaults.data(forKey: "tileColors"))
        manualCount = max(6, defaults.object(forKey: "manualWindowCount") as? Int ?? 12)
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "launcherProfiles") }
        if let data = try? JSONEncoder().encode(profiles.first { $0.id == "default" }?.items ?? profiles[0].items) {
            defaults.set(data, forKey: "pinnedItems")
        }
        if let data = try? JSONEncoder().encode(commands) { defaults.set(data, forKey: "menuCommands") }
        if let data = try? JSONEncoder().encode(menuHistory) { defaults.set(data, forKey: "menuHistoryPreferences") }
        if let data = try? JSONEncoder().encode(menuCapture) { defaults.set(data, forKey: "menuCapturePreferences") }
        defaults.set(manualProfileID, forKey: "manualProfileID")
        defaults.set(followFocus, forKey: "followFocus")
        defaults.set(numberShortcuts.rawValue, forKey: "numberShortcuts")
        defaults.set(automatic, forKey: "automaticWindowCount")
        defaults.set(optionTriggerEnabled, forKey: "optionTriggerEnabled")
        if let data = try? JSONEncoder().encode(optionReopen) { defaults.set(data, forKey: "optionReopenPreferences") }
        defaults.set(theme.rawValue, forKey: "appearanceTheme")
        if let data = try? JSONEncoder().encode(tileColors) { defaults.set(data, forKey: "tileColors") }
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
        let original = Self.webAppIcon(url) ?? NSWorkspace.shared.icon(forFile: url.path)
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        original.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        image.unlockFocus()
        cache.setObject(image, forKey: key)
        return image
    }
    /// Safari web-app icon lookup can trigger IconServices bundle maintenance.
    /// Read the declared resource ourselves; missing icons use a system symbol.
    static func webAppIcon(_ url: URL) -> NSImage? {
        guard url.pathExtension.lowercased() == "app",
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              (info["CFBundleIdentifier"] as? String)?.hasPrefix("com.apple.Safari.WebApp.") == true else { return nil }
        if let name = info["CFBundleIconFile"] as? String, !name.isEmpty,
           !name.contains("/"), !name.contains("\\"), name != ".", name != ".." {
            let resource = url.appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(name)
            let candidates = resource.pathExtension.isEmpty ? [resource, resource.appendingPathExtension("icns")] : [resource]
            for candidate in candidates {
                if let image = NSImage(contentsOf: candidate) { return image }
            }
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}
