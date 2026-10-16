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
    case original, squares, mixedNeutral, consecutiveSmall, grouped, locationColor
    var uniform: Bool { self == .squares || self == .consecutiveSmall || self == .grouped || self == .locationColor }
    var neutralApplications: Bool { self != .original }
}
/// R135 selects gray 2×2 recent menus; earlier variants remain for comparison previews.
enum MenuAppearance {
    case original, recentPastel, recentGraySquare
    static let selected: Self = .recentGraySquare
}
struct WindowItem: Identifiable, Equatable {
    let id: UUID
    let pid: pid_t
    let appName: String
    let appURL: URL?
    let title: String
    let minimized: Bool
    var windowID: CGWindowID? = nil
    var appID: String? = nil
    var desktop: WindowDesktop = .unknown
    var isApplication = false
    var runningApplication: NSRunningApplication? = nil
    var bounds: CGRect? = nil
    var location: RecentWindowLocation = .unknown
    /// R192: this tile continues another device's activity instead of a window.
    var handoff: HandoffItem? = nil
    var appKey: String {
        appID.map { "app:\($0)" } ?? appURL.map { "file:\($0.standardizedFileURL.path)" } ?? "pid:\(pid)"
    }
}
extension PinnedItem {
    var url: URL {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? URL(fileURLWithPath: path)
    }
}
extension MenuCommand {
    /// A symbol name only when this macOS has it installed.
    static func installed(_ name: String?) -> String? {
        MenuSymbolName.normalized(name).flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 }
    }
    var presetSymbol: String? { Self.installed(MenuSymbolPreset.symbol(for: title)) }
    var glyph: MenuTileGlyph {
        let choice = symbol == MenuSymbolName.hidden ? symbol : Self.installed(symbol)
        let resource = choice == nil ? resourceIcon.flatMap { SavedMenuImages.image($0) == nil ? nil : $0 } : nil
        return MenuTileGlyph.resolve(symbol: choice, preset: presetSymbol, shortcut: shortcut, resource: resource)
    }
    var usageDescription: String {
        "누적 \(totalUseCount)회 · 메뉴 막대 \(observedCount)회 · Tile Launcher \(useCount)회"
    }
}
enum OverlayMenuEntry {
    case command(MenuCommand), appSettings
    var isPinned: Bool {
        switch self { case .command(let command): command.isPinned; case .appSettings: true }
    }
    func isFrequent(_ ids: Set<UUID>) -> Bool {
        switch self { case .command(let command): ids.contains(command.id); case .appSettings: false }
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
    /// Action context survives display-only Handoff replacement and list limits.
    var menuContextWindow: WindowItem? = nil
    var hasAppSettings = false
    var appSettingsPending = false
    func menuEntries(commands override: [MenuCommand]? = nil) -> [OverlayMenuEntry] {
        (override ?? commands).map(OverlayMenuEntry.command)
            + (context != nil && permission && (hasAppSettings || appSettingsPending) ? [.appSettings] : [])
    }
    func workRows(commands override: [MenuCommand]? = nil) -> CGFloat {
        let geometry = DeckGeometry(width: layout.contentSize.width, compact: layout.compact, scale: layout.scale)
        return WorkAreaRows.visible(menuSpans: menuEntries(commands: override).map { $0.isPinned ? 2 : 1 },
            windowSizes: windows.map { $0.isApplication ? .application : $0.location.size },
            windowColumns: geometry.windowColumns, compact: layout.compact)
    }
}
final class OverlayContent: ObservableObject {
    @Published var snapshot: OverlaySnapshot
    init(_ snapshot: OverlaySnapshot) { self.snapshot = snapshot }
    static func activeAppKey(_ context: AppItem?, in windows: [WindowItem]) -> String? {
        guard let context else { return nil }
        return windows.first {
            $0.appID == context.id || $0.pid == context.pid
                || (context.url != nil && $0.appURL?.standardizedFileURL == context.url?.standardizedFileURL)
        }?.appKey
    }
    static func groupedWindows(_ windows: [WindowItem], context: AppItem?) -> [WindowItem] {
        GroupedRecentWindows.order(apps: windows.map(\.appKey), activeApp: activeAppKey(context, in: windows))
            .map { windows[$0] }
    }
    /// One stable identity for the Handoff tile across refreshes.
    static let handoffID = UUID()
    /// R192: a Handoff offer takes over the first tile — the window already in
    /// front, so nothing useful is lost — keeping its size so the layout does
    /// not move. With no windows it becomes the only tile.
    static func recentWindows(_ windows: [WindowItem], context: AppItem?, handoff: HandoffItem?) -> [WindowItem] {
        applyHandoff(handoff, to: recentWindows(windows, context: context))
    }
    static func applyHandoff(_ handoff: HandoffItem?, to list: [WindowItem]) -> [WindowItem] {
        var result = list
        guard let handoff else { return result }
        var tile = WindowItem(id: handoffID, pid: 0, appName: handoff.appName, appURL: handoff.appURL,
                              title: "Handoff", minimized: false, handoff: handoff)
        tile.location = result.first?.location ?? .activeDisplay
        if result.isEmpty { result = [tile] } else { result[0] = tile }
        return result
    }
    static func recentWindows(_ windows: [WindowItem], context: AppItem?) -> [WindowItem] {
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(id.uint32Value)
        }
        // The tracker's list is already individual-window MRU. Its first visible
        // window for the active app supplies the active monitor, not the cursor.
        let activeKey = activeAppKey(context, in: windows)
        let focused = windows.first { !$0.isApplication && $0.appKey == activeKey && $0.desktop == .current && $0.bounds != nil }
        let active = RecentWindowPolicy.display(containing: focused?.bounds, displays: displays)
        return windows.map { window in
            var item = window
            item.location = RecentWindowPolicy.location(desktop: window.desktop, bounds: window.bounds,
                                                        displays: displays, activeDisplay: active)
            return item
        }
    }
    func refresh(context: AppItem?, apps: [AppItem], windows: [WindowItem],
                 trusted: Bool, commands: [MenuCommand], manualCount: Int?,
                 menuHistory: MenuHistoryPreferences = .init(), handoff: HandoffItem? = nil,
                 hasAppSettings: Bool = false, appSettingsPending: Bool = false, now: Date = Date()) {
        let old = snapshot
        let recent = Self.recentWindows(windows, context: context, handoff: handoff)
        let count = old.layout.windowLimit(manual: manualCount, actual: recent.count)
        let next = OverlaySnapshot(context: context,
                                   contextWindowTitle: windows.first { $0.pid == context?.pid && !$0.isApplication }?.title,
                                   apps: Array(apps.prefix(3)), windows: Array(recent.prefix(count)),
                                   layout: old.layout, permission: trusted, pins: old.pins,
                                   profileID: old.profileID, profileName: old.profileName, shortcuts: old.shortcuts,
                                   commands: MenuCommand.ordered(commands, appID: context?.id ?? "", history: menuHistory, at: now),
                                   frequentMenuIDs: MenuCommand.frequentIDs(commands, appID: context?.id ?? "", history: menuHistory, at: now),
                                   menuContextWindow: windows.first { $0.pid == context?.pid && !$0.isApplication && $0.handoff == nil },
                                   hasAppSettings: hasAppSettings, appSettingsPending: appSettingsPending)
        if next != old { snapshot = next }
    }
}
final class SettingsStore: ObservableObject {
    @Published private(set) var importingDock = false
    @Published private var dockImportMessages: [String: String] = [:]
    var dockImportMessage: String? { dockImportMessages[activeProfile.id] }
    @Published var dockImportPreview: DockImportChange?
    @Published private var dockImportUndo: [String: DockImportChange] = [:]
    private var dockImportRequest: UUID?
    @Published var profiles: [LauncherProfile] {
        didSet {
            dockImportUndo = dockImportUndo.filter { id, change in
                profiles.first(where: { $0.id == id }).flatMap { change.undoing(in: $0) } != nil
            }
            save()
        }
    }
    @Published var manualProfileID: String { didSet { save() } }
    @Published var followFocus: Bool { didSet { save() } }
    @Published var focusProfileID: String?
    @Published var numberShortcuts: NumberShortcutAssignment { didSet { save() } }
    @Published var commands: [MenuCommand] { didSet { save() } }
    @Published var menuHistory: MenuHistoryPreferences { didSet { save() } }
    @Published var menuRecentDaysInput = "30"
    @Published var menuFrequentDaysInput = "90"
    var validMenuHistoryInput: MenuHistoryPreferences? {
        guard let recent = Int(menuRecentDaysInput.trimmingCharacters(in: .whitespaces)),
              let frequent = Int(menuFrequentDaysInput.trimmingCharacters(in: .whitespaces)),
              MenuHistoryPreferences.dayRange.contains(recent),
              MenuHistoryPreferences.dayRange.contains(frequent) else { return nil }
        return MenuHistoryPreferences(recentDays: recent, frequentDays: frequent)
    }
    func updateMenuHistoryInput() {
        if let value = validMenuHistoryInput, value != menuHistory { menuHistory = value }
    }
    @Published var menuCapture: MenuCapturePreferences { didSet { save() } }
    @Published var showAppSettingsTile: Bool {
        didSet { save(); onAppSettingsVisibilityChanged?(showAppSettingsTile) }
    }
    @Published var menuCaptureStatus: [String: String] = [:]
    @Published var refreshingMenuIcons: Set<String> = []
    @Published var menuIconStatus: [String: String] = [:]
    // Wired only by the production delegate; previews/tests never inspect apps.
    var onMenuAdded: ((MenuCommand) -> Void)?
    var onRefreshMenuIcons: ((String) -> Void)?
    var onAppSettingsVisibilityChanged: ((Bool) -> Void)?
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
        let restored = Set(MenuPathMatch.paths(command).map { MenuIdentity(appID: command.appID, path: $0) })
        menuCapture.excludedMenus.subtract(restored)
        guard MenuCaptureHistory.index(of: MenuIdentity(appID: command.appID, path: command.path), in: commands) == nil else { return }
        commands.append(command)
        onMenuAdded?(command)
    }
    func recordCapturedMenu(_ menu: CapturedMenu) {
        guard MenuCapturePolicy.allows(menu, preferences: menuCapture) else { return }
        let isNew = MenuCaptureHistory.index(of: menu.identity, in: commands) == nil
        commands = MenuCaptureHistory.record(menu, in: commands, at: Date())
        if isNew, let added = commands.first(where: { $0.appID == menu.identity.appID && $0.path == menu.identity.path }) { onMenuAdded?(added) }
    }
    func removeCommand(_ command: MenuCommand) {
        menuCapture.excludedMenus.formUnion(MenuPathMatch.paths(command).map { MenuIdentity(appID: command.appID, path: $0) })
        commands.removeAll { $0.id == command.id }
    }
    func clearCapturedMenus(appID: String) {
        commands.removeAll { $0.appID == appID && $0.isAutomatic && !$0.isPinned }
    }
    func togglePin(_ id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[i].isPinned.toggle()
    }
    func setSymbol(_ name: String?, for id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        let symbol = MenuSymbolName.stored(name)
        if commands[i].symbol != symbol { commands[i].symbol = symbol }
    }
    /// The app's current keyboard equivalent; nil clears a removed shortcut.
    func updateShortcut(_ shortcut: MenuShortcut?, for id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }), commands[i].shortcut != shortcut else { return }
        commands[i].shortcut = shortcut
    }
    func recordUse(_ id: UUID) {
        guard let i = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[i].recordUse(at: Date())
    }
    func moveCommand(_ id: UUID, by offset: Int) {
        guard let target = MenuCommand.pinnedMoveTarget(for: id, by: offset, in: commands),
              let from = commands.firstIndex(where: { $0.id == id }),
              let to = commands.firstIndex(where: { $0.id == target }) else { return }
        commands.swapAt(from, to)
    }
    @Published var automatic: Bool { didSet { save() } }
    @Published var optionTriggerEnabled: Bool { didSet { save() } }
    @Published var optionReopen: OptionReopenPreferences { didSet { save() } }
    @Published var theme: DeckTheme { didSet { save() } }
    @Published var tileColors: TileColors { didSet { save() } }
    @Published var manualCount: Int { didSet { save() } }
    private let defaults: UserDefaults
    private let persistsChanges: Bool
    private var saveDepth = 0
    private var pendingSave = false
    init(defaults: UserDefaults = .standard, persistsChanges: Bool = true) {
        self.defaults = defaults
        self.persistsChanges = persistsChanges
        profiles = LauncherProfile.restore(profiles: defaults.data(forKey: "launcherProfiles"),
                                           legacyPins: defaults.data(forKey: "pinnedItems"))
        manualProfileID = defaults.string(forKey: "manualProfileID") ?? "default"
        followFocus = defaults.object(forKey: "followFocus") as? Bool ?? true
        numberShortcuts = defaults.string(forKey: "numberShortcuts").flatMap(NumberShortcutAssignment.init(rawValue:)) ?? .registeredFirst
        commands = defaults.data(forKey: "menuCommands").flatMap { try? JSONDecoder().decode([MenuCommand].self, from: $0) } ?? []
        menuHistory = MenuHistoryPreferences.restore(defaults.data(forKey: "menuHistoryPreferences"))
        menuCapture = MenuCapturePreferences.restore(defaults.data(forKey: "menuCapturePreferences"))
        showAppSettingsTile = defaults.object(forKey: "showAppSettingsTile") as? Bool ?? true
        automatic = defaults.object(forKey: "automaticWindowCount") as? Bool ?? true
        optionTriggerEnabled = defaults.object(forKey: "optionTriggerEnabled") as? Bool ?? true
        optionReopen = OptionReopenPreferences.restore(defaults.data(forKey: "optionReopenPreferences"))
        theme = defaults.string(forKey: "appearanceTheme").flatMap(DeckTheme.init(rawValue:))
            ?? .glass
        tileColors = TileColors.restore(defaults.data(forKey: "tileColors"))
        manualCount = max(6, defaults.object(forKey: "manualWindowCount") as? Int ?? 12)
        menuRecentDaysInput = String(menuHistory.recentDays)
        menuFrequentDaysInput = String(menuHistory.frequentDays)
        save()
    }
    func makeEditingCopy() -> SettingsStore {
        let copy = SettingsStore(defaults: defaults, persistsChanges: false)
        copy.profiles = profiles; copy.manualProfileID = manualProfileID; copy.followFocus = followFocus
        copy.focusProfileID = focusProfileID; copy.numberShortcuts = numberShortcuts
        copy.commands = commands; copy.menuHistory = menuHistory; copy.menuCapture = menuCapture
        copy.menuRecentDaysInput = String(menuHistory.recentDays)
        copy.menuFrequentDaysInput = String(menuHistory.frequentDays)
        copy.showAppSettingsTile = showAppSettingsTile
        copy.automatic = automatic; copy.optionTriggerEnabled = optionTriggerEnabled
        copy.optionReopen = optionReopen; copy.theme = theme; copy.tileColors = tileColors
        copy.manualCount = manualCount
        return copy
    }
    func batchSave(_ changes: () -> Void) {
        saveDepth += 1
        changes()
        saveDepth -= 1
        if saveDepth == 0, pendingSave { pendingSave = false; save() }
    }
    private func save() {
        guard persistsChanges else { return }
        guard saveDepth == 0 else { pendingSave = true; return }
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "launcherProfiles") }
        if let data = try? JSONEncoder().encode(profiles.first { $0.id == "default" }?.items ?? profiles[0].items) {
            defaults.set(data, forKey: "pinnedItems")
        }
        if let data = try? JSONEncoder().encode(commands) { defaults.set(data, forKey: "menuCommands") }
        if let data = try? JSONEncoder().encode(menuHistory) { defaults.set(data, forKey: "menuHistoryPreferences") }
        if let data = try? JSONEncoder().encode(menuCapture) { defaults.set(data, forKey: "menuCapturePreferences") }
        defaults.set(showAppSettingsTile, forKey: "showAppSettingsTile")
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
        guard !importingDock, dockImportPreview == nil else { return }
        importingDock = true
        let request = UUID()
        dockImportRequest = request
        let targetProfileID = activeProfile.id
        dockImportMessages.removeValue(forKey: targetProfileID)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DockImporter.load() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.dockImportRequest == request else { return }
                self.dockImportRequest = nil
                self.importingDock = false
                switch result {
                case .success(let imported):
                    self.previewDockImport(imported, profileID: targetProfileID)
                case .failure(let error): self.dockImportMessages[targetProfileID] = error.localizedDescription
                }
            }
        }
    }
    func previewDockImport(_ imported: DockImportResult, profileID: String) {
        guard let target = profiles.first(where: { $0.id == profileID }) else {
            dockImportMessages[activeProfile.id] = "가져올 프로필이 없어졌습니다. 프로필을 선택한 뒤 다시 시도하세요."
            return
        }
        let change = DockImportChange(profile: target, imported: imported)
        guard change.hasChanges else {
            dockImportMessages[profileID] = "이미 같은 목록과 순서입니다."
            return
        }
        dockImportPreview = change
    }
    func cancelDockImport() {
        dockImportRequest = nil
        importingDock = false
        dockImportPreview = nil
    }
    func applyDockImport(_ change: DockImportChange) {
        guard dockImportPreview?.id == change.id else { return }
        dockImportPreview = nil
        guard let target = profiles.first(where: { $0.id == change.profileID }),
              let items = change.applying(to: target) else {
            dockImportMessages[activeProfile.id] = "‘\(change.profileName)’의 목록이 바뀌었습니다. 다시 가져와서 확인하세요."
            return
        }
        setItems(items, profileID: change.profileID)
        dockImportUndo[change.profileID] = change
        dockImportMessages[target.id] = "‘\(target.name)’에 \(change.addedIDs.count)개 추가 · Dock 순서로 정리했습니다."
    }
    var canUndoDockImport: Bool {
        dockImportUndo[activeProfile.id]?.undoing(in: activeProfile) != nil
    }
    func undoDockImport() {
        let target = activeProfile
        guard let change = dockImportUndo[target.id], let items = change.undoing(in: target) else { return }
        dockImportUndo.removeValue(forKey: target.id)
        setItems(items, profileID: target.id)
        dockImportMessages[target.id] = "‘\(target.name)’을 Dock에서 가져오기 전 목록으로 되돌렸습니다."
    }
}

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 96 }
    func isCached(_ url: URL) -> Bool { cache.object(forKey: url.path as NSString) != nil }
    func icon(_ url: URL?) -> NSImage {
        guard let url else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        let original = Self.webAppIcon(url) ?? NSWorkspace.shared.icon(forFile: url.path)
        // Keep all native/ICNS representations for the larger physical icons.
        // Flattening into a 64pt bitmap discards higher-resolution variants.
        let image = (original.copy() as? NSImage) ?? original
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
