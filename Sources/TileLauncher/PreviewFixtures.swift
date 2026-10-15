import AppKit
import SwiftUI
import DeckCore

/// Only populated by the realistic comparison fixture. Read icon resources, never launch apps.
enum PreviewIconAssets {
    private static var images: [String: NSImage] = [:]
    static func image(for url: URL?) -> NSImage? { url.flatMap { images[$0.path] } }
    static func app(_ name: String, path: String, iconFile: String? = nil, fallback: String = "app.fill") -> URL {
        let key = URL(fileURLWithPath: "/Preview/Realistic/\(name).app")
        if images[key.path] != nil { return key }
        let bundle = URL(fileURLWithPath: path)
        let info = (try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let resourceName = iconFile ?? info?["CFBundleIconFile"] as? String
        let resource = resourceName.map { bundle.appendingPathComponent("Contents/Resources").appendingPathComponent($0) }
        let original = resource.flatMap { NSImage(contentsOf: $0) ?? NSImage(contentsOf: $0.appendingPathExtension("icns")) }
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil)!
        let bitmap = NSImage(size: NSSize(width: 256, height: 256))
        bitmap.lockFocus()
        original.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        bitmap.unlockFocus()
        images[key.path] = bitmap
        return key
    }
    static func folder(_ name: String) -> PinnedItem {
        let key = "/Preview/Realistic/\(name)"
        let image = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns")
            ?? NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)!
        let bitmap = NSImage(size: NSSize(width: 256, height: 256))
        bitmap.lockFocus()
        NSColor.systemBlue.set()
        image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        bitmap.unlockFocus()
        images[key] = bitmap
        return PinnedItem(kind: .folder, path: key, bundleID: nil, name: name)
    }
}

/// Synthetic data only: no AX observer, keyboard monitor, real folder or user settings.
final class PreviewFixture: ObservableObject {
    let settings: SettingsStore
    let content: OverlayContent
    let presentation = OverlayPresentation()
    let browser = FolderBrowser()
    private let suite: String
    private let defaults: UserDefaults
    init(theme: DeckTheme, customColors: Bool = false, compact: Bool = false, registeredCount: Int = 35, comparisonSample: Bool = false, recentCount: Int = 16, menuComparison: Bool = false, realisticSample: Bool = false, groupedRecent: Bool = false) {
        suite = "dev.cola16.TileLauncher.preview.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults)
        settings.theme = theme
        if menuComparison { settings.tileColors.menus = TileColor(0x4CBB00) }
        if customColors {
            settings.tileColors.menus = TileColor(0xAA4725)
            settings.tileColors.windows = TileColor(0x7651AA)
            settings.tileColors.registered = TileColor(0x297D76)
        }
        var pins = (0..<registeredCount).map { PinnedItem(kind: .app, path: "/Preview/App\($0).app", bundleID: nil, name: "앱 \($0 + 1)") }
        var realisticApps: [String: URL] = [:]
        if realisticSample {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let entries: [(String, String, String?)] = [
                ("Finder", "/System/Library/CoreServices/Finder.app", nil),
                ("ChatGPT", "/Applications/AI/ChatGPT.app", "icon-chatgpt.icns"),
                ("Claude", "/Applications/AI/Claude.app", nil),
                ("Slack", "/Applications/Slack.app", nil),
                ("CotEditor", "/Applications/Develop/CotEditor.app", nil),
                ("Preview", "/System/Applications/Preview.app", nil),
                ("Docmost", home + "/Applications/safariDock/OPENMARU/Docmost - kanban.app", nil),
                ("Outline", home + "/Applications/Outline.app", nil),
                ("iTerm2", "/Applications/Develop/iTerm.app", nil),
                ("Spark", "/Applications/Spark Desktop.app", nil),
                ("Safari", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", nil),
                ("Notes", "/System/Applications/Notes.app", nil),
                ("Hi Sticky", "/Applications/Hi Sticky.app", nil),
                ("Calendar", "/System/Applications/Calendar.app", nil),
                ("Reminders", "/System/Applications/Reminders.app", nil)
            ]
            for (name, path, icon) in entries { realisticApps[name] = PreviewIconAssets.app(name, path: path, iconFile: icon) }
            let names = ["Finder", "Safari", "ChatGPT", "Docmost", "CotEditor", "Slack", "Notes", "iTerm2",
                         "Preview", "Hi Sticky", "Spark", "Calendar", "Reminders"]
            pins = names.map { PinnedItem(kind: .app, path: realisticApps[$0]!.path, bundleID: nil, name: $0) }
            pins += [PreviewIconAssets.folder("Projects"), PreviewIconAssets.folder("Downloads"),
                     PinnedItem(kind: .trash, path: "/Preview/Realistic/Trash", bundleID: nil, name: "휴지통")]
            pins += ["Outline", "Claude"].map { PinnedItem(kind: .app, path: realisticApps[$0]!.path, bundleID: nil, name: $0) }
        }
        settings.pins = pins
        let app = AppItem(id: "preview.editor", pid: -1, name: menuComparison ? "Finder" : "문서 편집기", url: nil)
        var commands = [
            MenuCommand(appID: app.id, appName: app.name, path: ["파일", "PDF로 내보내기"]),
            MenuCommand(appID: app.id, appName: app.name, path: ["도구", "그림 크기 줄이기"]),
            MenuCommand(appID: app.id, appName: app.name, path: ["파일", "저장"], isPinned: false),
            MenuCommand(appID: app.id, appName: app.name, path: ["이동", "폴더로 이동…"], isPinned: false),
            MenuCommand(appID: app.id, appName: app.name, path: ["보기", "확대"], isPinned: false)
        ]
        for _ in 0..<3 { commands[0].recordUse(at: Date()) }
        for _ in 0..<2 { commands[0].recordUse(at: Date(), observed: true) }
        for _ in 0..<4 { commands[2].recordUse(at: Date()) }
        commands[3].recordUse(at: Date())
        if menuComparison {
            let paths = [["File", "New Tab"], ["File", "New Folder"], ["File", "New Finder Window"],
                         ["File", "Open in New Tab"], ["File", "Get Info"], ["Go", "Go to Folder…"],
                         ["Go", "Connect to Server…"], ["View", "Show View Options"], ["View", "Hide Sidebar"]]
            commands = paths.enumerated().map { index, path in
                var command = MenuCommand(appID: app.id, appName: app.name, path: path, isPinned: index < 3)
                for _ in 0..<([3, 2, 1, 3, 4, 2, 1, 1, 1][index]) { command.recordUse(at: Date()) }
                // Finder's real equivalents; Open in New Tab has none.
                command.shortcut = [("t", 0), ("n", 1), ("n", 0), nil, ("i", 0), ("g", 1), ("k", 0), ("j", 0), ("s", 4)][index]
                    .flatMap { MenuShortcut(key: $0.0, modifiers: $0.1) }
                // Built-in defaults cover most Finder titles; one user choice and one
                // explicit “no icon” show the other paths.
                command.symbol = [nil, nil, "macwindow.badge.plus", nil, nil, nil, MenuSymbolName.hidden, nil, nil][index]
                return command
            }
        }
        settings.commands = commands
        var windows: [WindowItem] = []
        let iconURLs = ["terminal", "externaldrive", "note.text", "calendar", "plus", "music.note"].map { URL(string: "tile-preview://\($0)/\($0)")! }
        let sampleGroups = [0, 0, 1, 4, 2, 2, 1, 5, 0, 0, 0, 3, 3, 2, 2, 1]
        let sampleNames = ["Terminal", "Finder", "메모", "캘린더", "계산기", "음악"]
        let sampleTitles = ["cc2", "se3", "", "", "기획 노트", "회의 기록", "다운로드", "", "개발 서버", "로컬 로그", "배포 로그", "이번 주", "다음 주", "설계 문서", "변경 이력", "프로젝트"]
        for index in 0..<(comparisonSample ? 16 : recentCount) {
            let pid: pid_t = index < 2 ? 1 : Int32(index)
            let applicationOnly = [2, 3, 7].contains(index)
            let name = index == 2 ? "USBClean" : index < 2 ? "Terminal" : "앱 \(index + 1)"
            let title = index == 0 ? "cc2" : (index == 1 ? "se3" : "프로젝트 문서 \(index + 1)")
            let desktop: WindowDesktop = index < 4 ? .current : .other
            let group = comparisonSample ? sampleGroups[index] : index < 2 ? 0 : index % 4
            windows.append(WindowItem(id: UUID(), pid: comparisonSample ? (index == 2 ? 99 : Int32(group + 1)) : pid,
                                      appName: comparisonSample ? (index == 2 ? "USBClean" : sampleNames[group]) : name,
                                      appURL: comparisonSample && index == 2 ? URL(string: "tile-preview://externaldrive/usbclean") : iconURLs[group],
                                      title: applicationOnly ? "" : comparisonSample ? sampleTitles[index] : title, minimized: false,
                                      desktop: applicationOnly ? .unknown : desktop, isApplication: applicationOnly))
        }
        if realisticSample {
            let samples: [(String, String, WindowDesktop, Bool)] = [
                ("Finder", "Downloads", .current, false),
                ("ChatGPT", "ChatGPT", .current, false),
                ("Finder", "launch at Login", .current, false),
                ("Finder", "개발", .other, false),
                ("CotEditor", "", .unknown, true),
                ("Preview", "", .unknown, true),
                ("ChatGPT", "설정 창 여백 검토", .other, false),
                ("ChatGPT", "메뉴 타일 비교", .current, false),
                ("Docmost", "프로젝트 칸반", .current, false),
                ("Docmost", "서비스 작업 목록", .other, false),
                ("Docmost", "이번 주 일정", .other, false),
                ("Outline", "", .unknown, true),
                ("Claude", "새 릴리스 준비", .other, false),
                ("Claude", "집중 모드 연동", .other, false),
                ("Claude", "UI 개선 메모", .other, false),
                ("Claude", "앱 메뉴 수집", .other, false),
                ("Slack", "# 프로젝트 · 팀 대화", .current, false),
                ("iTerm2", "~ — zsh", .current, false),
                ("Spark", "", .unknown, true)
            ]
            windows = samples.enumerated().map { index, sample in
                WindowItem(id: UUID(), pid: Int32(index + 100), appName: sample.0, appURL: realisticApps[sample.0],
                           title: sample.1, minimized: false, desktop: sample.2, isApplication: sample.3)
            }
        }
        let layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: compact ? 560 : 1440,
                                                                height: compact ? 468 : 1000),
                                           cursor: CGPoint(x: 720, y: 500)).fittingContent(registeredCount: pins.count)
        let previewContext = groupedRecent ? AppItem(id: app.id, pid: windows.first?.pid ?? app.pid,
                                                     name: app.name, url: windows.first?.appURL) : app
        let displayed = groupedRecent ? OverlayContent.groupedWindows(windows, context: previewContext) : windows
        content = OverlayContent(OverlaySnapshot(context: previewContext, contextWindowTitle: menuComparison ? "Downloads" : "미리보기 문서",
                    apps: [previewContext], windows: displayed, layout: layout, permission: true, pins: pins,
                    profileID: "default", profileName: "기본", shortcuts: .registeredFirst, commands: commands,
                    frequentMenuIDs: MenuCommand.frequentIDs(commands, appID: app.id)))
        presentation.profile = settings.activeProfile
        presentation.windowDesktops = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
        // Keep the synthetic panel unpinned, so its drag representable cannot affect a preview host window.
    }
    deinit { defaults.removePersistentDomain(forName: suite) }
    func verifyFocusSelection() throws {
        let originalProfiles = settings.profiles
        let originalManual = settings.manualProfileID
        let originalFollow = settings.followFocus
        let originalFocus = settings.focusProfileID
        defer {
            settings.profiles = originalProfiles; settings.manualProfileID = originalManual
            settings.followFocus = originalFollow; settings.focusProfileID = originalFocus
        }
        settings.profiles = ["default", "manual", "work"].map { LauncherProfile(id: $0, name: $0) }
        settings.manualProfileID = "manual"
        settings.focusProfileID = "work"
        settings.followFocus = false
        guard settings.activeProfile.id == "manual" else { throw NSError(domain: "TileLauncher.Preview", code: 20) }
        settings.followFocus = true
        guard settings.activeProfile.id == "work" else { throw NSError(domain: "TileLauncher.Preview", code: 21) }
        settings.focusProfileID = nil
        guard settings.activeProfile.id == "manual" else { throw NSError(domain: "TileLauncher.Preview", code: 22) }
        settings.focusProfileID = "deleted-profile"
        guard settings.activeProfile.id == "manual" else { throw NSError(domain: "TileLauncher.Preview", code: 23) }
        settings.manualProfileID = "deleted-manual"
        guard settings.activeProfile.id == "default" else { throw NSError(domain: "TileLauncher.Preview", code: 24) }
        print("SettingsStore: Focus opt-in, active mapping, cleared/deleted filter and missing manual fallback passed.")
    }
    func verifySettingsRoundTrip() throws {
        let before = content.snapshot
        let now = Date()
        func refresh(at date: Date) {
            content.refresh(context: before.context, apps: before.apps, windows: before.windows,
                            trusted: true, commands: settings.commands, manualCount: nil, now: date)
        }
        refresh(at: now)
        let current = content.snapshot
        refresh(at: now.addingTimeInterval(1))
        guard content.snapshot == current, !current.frequentMenuIDs.isEmpty else {
            throw NSError(domain: "TileLauncher.Preview", code: 8)
        }
        refresh(at: now.addingTimeInterval(91 * 86_400))
        guard content.snapshot.frequentMenuIDs.isEmpty, !before.frequentMenuIDs.isEmpty else {
            throw NSError(domain: "TileLauncher.Preview", code: 9)
        }
        print("OverlayContent: stable snapshot equality and date-based frequency refresh passed.")
        let originalProfiles = settings.profiles
        let originalCommands = settings.commands
        guard settings.optionReopen == OptionReopenPreferences() else {
            throw NSError(domain: "TileLauncher.Preview", code: 45)
        }
        settings.optionReopen = .init(enabled: false, interval: 1.2)
        settings.tileColors.menus = TileColor(0xCC7722)
        settings.tileColors.windows = TileColor(0x7766BB)
        settings.tileColors.registered = TileColor(0x448877)
        let expectedColors = settings.tileColors
        settings.theme = .glass
        settings.menuHistory = MenuHistoryPreferences(recentDays: 45, frequentDays: 120)
        let restored = SettingsStore(defaults: defaults)
        guard restored.tileColors == expectedColors, restored.theme == .glass,
              restored.menuHistory == settings.menuHistory,
              restored.optionReopen == OptionReopenPreferences(enabled: false, interval: 1.2),
              restored.profiles == originalProfiles, restored.commands == originalCommands else {
            throw NSError(domain: "TileLauncher.Preview", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Settings persistence regression"])
        }
        restored.tileColors.windows = nil
        let reset = SettingsStore(defaults: defaults)
        guard reset.tileColors.windows == nil, reset.tileColors.menus == expectedColors.menus,
              reset.tileColors.registered == expectedColors.registered else {
            throw NSError(domain: "TileLauncher.Preview", code: 4)
        }
        print("SettingsStore: history periods, section colors, theme switch, single-section reset and existing data preservation passed.")
        settings.optionReopen = .init(interval: 0.3)
        guard SettingsStore(defaults: defaults).optionReopen == OptionReopenPreferences(interval: 0.3) else {
            throw NSError(domain: "TileLauncher.Preview", code: 46)
        }
        print("SettingsStore: Option recovery default 0.6, disabled/custom interval persistence and existing data preservation passed.")
        let captured = CapturedMenu(appID: "preview.editor", appName: "문서 편집기", path: ["편집", "복사"],
                                    shortcut: "c", commandModifier: true)
        settings.recordCapturedMenu(captured)
        let menusRestored = SettingsStore(defaults: defaults)
        guard let copy = menusRestored.commands.first(where: { $0.path == captured.identity.path }),
              copy.isAutomatic, !copy.isPinned, copy.observedCount == 1, copy.recentUses.count == 1 else {
            throw NSError(domain: "TileLauncher.Preview", code: 5)
        }
        menusRestored.removeCommand(copy)
        menusRestored.recordCapturedMenu(captured)
        guard !menusRestored.commands.contains(where: { $0.id == copy.id || $0.path == copy.path }) else {
            throw NSError(domain: "TileLauncher.Preview", code: 6)
        }
        menusRestored.menuCapture.excludedApps.insert("preview.editor")
        menusRestored.menuCapture.excludedMenus = []
        menusRestored.recordCapturedMenu(captured)
        menusRestored.menuCapture.enabled = false
        let paused = SettingsStore(defaults: defaults)
        guard !paused.menuCapture.enabled, paused.menuCapture.excludedApps.contains("preview.editor"),
              paused.profiles == originalProfiles else { throw NSError(domain: "TileLauncher.Preview", code: 7) }
        print("SettingsStore: automatic Copy capture, deletion exclusion, app pause and global pause persistence passed.")
        let pinned = MenuCommand(appID: "preview.counts", appName: "미리보기", path: ["File", "Export"])
        let selection = CapturedMenu(appID: pinned.appID, appName: pinned.appName, path: pinned.path)
        paused.addCommand(pinned)
        paused.recordUse(pinned.id)
        paused.recordUse(pinned.id)
        paused.recordCapturedMenu(selection) // Capture is off, launcher usage still counts.
        guard let launcherOnly = paused.commands.first(where: { $0.id == pinned.id }),
              launcherOnly.totalUseCount == 2, launcherOnly.useCount == 2, launcherOnly.observedCount == 0 else {
            throw NSError(domain: "TileLauncher.Preview", code: 10)
        }
        paused.menuCapture.enabled = true
        paused.recordCapturedMenu(selection)
        let counted = SettingsStore(defaults: defaults)
        guard let combined = counted.commands.first(where: { $0.id == pinned.id }),
              combined.isPinned, combined.totalUseCount == 3, combined.useCount == 2,
              combined.observedCount == 1, combined.recentUses.count == 3, combined.lastUsed != nil else {
            throw NSError(domain: "TileLauncher.Preview", code: 11)
        }
        counted.togglePin(pinned.id)
        guard let unpinned = counted.commands.first(where: { $0.id == pinned.id }),
              !unpinned.isPinned, unpinned.isFrequent(history: counted.menuHistory),
              MenuCommand.ordered(counted.commands, appID: pinned.appID, history: counted.menuHistory).contains(where: { $0.id == pinned.id }) else {
            throw NSError(domain: "TileLauncher.Preview", code: 12)
        }
        print("SettingsStore: pinned launcher-only counts while capture is off, combined counts/dates persistence and frequency after unpinning passed.")
    }
}

struct DeckPreview: View {
    @StateObject var fixture: PreviewFixture
    @StateObject var launches: ApplicationLaunchMonitor
    var recentAppearance: RecentAppearance
    var menuAppearance: MenuAppearance
    init(theme: DeckTheme, customColors: Bool = false, compact: Bool = false, registeredCount: Int = 35,
         recentAppearance: RecentAppearance = .locationColor, comparisonSample: Bool = false, recentCount: Int = 16,
         menuAppearance: MenuAppearance = .selected, realisticSample: Bool = false, deliveredScale: Bool = false,
         keyboardFeedback: Bool = false, launchFeedback: Bool = false) {
        self.recentAppearance = recentAppearance
        self.menuAppearance = menuAppearance
        let fixture = PreviewFixture(theme: theme, customColors: customColors,
                                                          compact: compact, registeredCount: registeredCount,
                                                          comparisonSample: comparisonSample, recentCount: recentCount,
                                                          menuComparison: comparisonSample || realisticSample,
                                                          realisticSample: realisticSample, groupedRecent: recentAppearance == .grouped)
        if deliveredScale {
            fixture.content.snapshot.layout = PanelLayout.calculate(
                visibleFrame: CGRect(x: 0, y: 0, width: compact ? 1024 : 2560, height: compact ? 768 : 1440),
                cursor: .zero, scale: PanelLayout.preferredScale).fittingContent(registeredCount: fixture.settings.pins.count)
        }
        if recentAppearance == .locationColor {
            // Synthetic monitor attribution; never inspect the user's windows.
            fixture.content.snapshot = OverlaySnapshot(context: fixture.content.snapshot.context,
                contextWindowTitle: fixture.content.snapshot.contextWindowTitle, apps: fixture.content.snapshot.apps,
                windows: fixture.content.snapshot.windows.enumerated().map { index, window in
                    var copy = window
                    copy.location = window.desktop == .current ? (index % 3 == 1 ? .otherVisibleDisplay : .activeDisplay)
                        : window.desktop == .other ? .hidden : .unknown
                    return copy
                }, layout: fixture.content.snapshot.layout, permission: true, pins: fixture.content.snapshot.pins,
                profileID: "default", profileName: "기본", shortcuts: .registeredFirst,
                commands: fixture.content.snapshot.commands, frequentMenuIDs: fixture.content.snapshot.frequentMenuIDs)
        }
        if keyboardFeedback, let pin = fixture.content.snapshot.pins.first {
            fixture.presentation.showExecution(target: "pin:\(pin.id)", title: pin.name)
        }
        let launches = ApplicationLaunchMonitor(running: { [] }, observesSystem: false, open: { _, _ in })
        if launchFeedback, let pin = fixture.content.snapshot.pins.first {
            launches.launch(at: pin.url, title: pin.name, failure: { _ in })
        }
        if recentAppearance == .locationColor {
            fixture.content.snapshot.layout = fixture.content.snapshot.layout.fittingContent(
                registeredCount: fixture.settings.pins.count, workRows: fixture.content.snapshot.workRows())
        }
        _launches = StateObject(wrappedValue: launches)
        _fixture = StateObject(wrappedValue: fixture)
    }
    var body: some View {
        DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                 presentation: fixture.presentation, launches: launches, selectApp: { _ in }, selectPin: { _ in },
                 selectMenu: { _, _, _ in }, changeProfile: { _ in }, cycleProfile: { _ in },
                 selectWindow: { _ in }, openURL: { _ in }, openInFinder: { _ in }, openTrash: {},
                 showSettings: { _ in }, requestPermission: {}, pinOverlay: {}, recentAppearance: recentAppearance,
                 menuAppearance: menuAppearance, dismiss: {})
            .frame(width: fixture.content.snapshot.layout.frame.width, height: fixture.content.snapshot.layout.frame.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DeckSurfaceView.cornerRadius, style: .continuous))
    }
}

struct AppearancePreview: View {
    @StateObject private var fixture: PreviewFixture
    init(theme: DeckTheme = .classic) {
        _fixture = StateObject(wrappedValue: PreviewFixture(theme: theme))
    }
    var body: some View {
        AppearanceView(settings: fixture.settings).frame(width: 580, height: 760)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MenuAdditionPreview: View {
    @StateObject private var fixture = PreviewFixture(theme: .glass)
    @StateObject private var catalog = MenuCatalog(initialChoices:
        (1...50).map { AvailableMenu(path: ["파일", "내보내기", "문서 내보내기 \($0)"]) })
    @State private var selectedID = "preview.editor"
    @State private var search = ""
    @State private var manualPath = ""
    let size: CGSize
    var manualExpanded = false
    var body: some View {
        MenuAdditionSheet(settings: fixture.settings, catalog: catalog, selectedID: $selectedID,
                          search: $search, manualPath: $manualPath,
                          appNames: [(id: "preview.editor", name: "문서 편집기")],
                          selectedApp: fixture.content.snapshot.context, size: size,
                          refreshApps: {}, dismiss: {}, manualExpanded: manualExpanded)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MenuUsagePreview: View {
    private let commands: [MenuCommand] = {
        var launcher = MenuCommand(appID: "preview", appName: "문서 편집기", path: ["도구", "그림 크기 줄이기"])
        for _ in 0..<3 { launcher.recordUse(at: Date()) }
        var combined = MenuCommand(appID: "preview", appName: "문서 편집기", path: ["파일", "PDF로 내보내기"])
        for _ in 0..<3 { combined.recordUse(at: Date()) }
        for _ in 0..<2 { combined.recordUse(at: Date(), observed: true) }
        let unused = MenuCommand(appID: "preview", appName: "문서 편집기", path: ["보기", "페이지에 맞추기"])
        return [launcher, combined, unused]
    }()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("메뉴 사용 횟수").font(.headline)
            ForEach(commands) { command in
                HStack {
                    MenuCommandDetails(command: command)
                    Spacer()
                    Image(systemName: "pin.fill").foregroundStyle(.secondary)
                }
            }
        }.padding(20).frame(width: 440).background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Real tab views with isolated preferences and a synthetic application roster.
struct SettingsLayoutPreview: View {
    @StateObject private var fixture = PreviewFixture(theme: .glass)
    @StateObject private var loginItem = LoginItemManager()
    @StateObject private var navigation = SettingsNavigation()
    let tab: SettingsTab
    let size: CGSize
    var emptyMenus = false
    var body: some View {
        SettingsView(settings: fixture.settings, loginItem: loginItem, navigation: navigation,
                     requestPermission: {}, openAppManagementSettings: {},
                     applicationProvider: { [fixture.content.snapshot.context].compactMap { $0 } })
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                navigation.tab = tab
                guard let app = fixture.content.snapshot.context else { return }
                fixture.settings.commands = emptyMenus ? [] : (1...24).map { index in
                    var command = MenuCommand(appID: app.id, appName: app.name,
                                              path: ["파일", "문서 작업 \(index)"])
                    command.isPinned = index <= 3
                    command.recordUse(at: Date(), observed: index % 2 == 0)
                    return command
                }
            }
    }
}

#Preview("클래식 · 기본색") { DeckPreview(theme: .classic).preferredColorScheme(.dark) }
#Preview("유리 · 기본색") { DeckPreview(theme: .glass).preferredColorScheme(.dark) }
#Preview("메뉴 비교 · 최근 파스텔") { DeckPreview(theme: .classic, registeredCount: 18, comparisonSample: true, menuAppearance: .recentPastel).preferredColorScheme(.dark) }
#Preview("메뉴 비교 · 최근 회색 2×2") { DeckPreview(theme: .classic, registeredCount: 18, comparisonSample: true, menuAppearance: .recentGraySquare).preferredColorScheme(.dark) }
#Preview("사용자 색 · 밝은 화면") { DeckPreview(theme: .classic, customColors: true).preferredColorScheme(.light) }
#Preview("모양 설정") { AppearancePreview() }
#Preview("메뉴 사용 횟수") { MenuUsagePreview() }
#Preview("일반 설정") { FittedSettingsPreview(tab: .general) }
#Preview("메뉴 설정") { FittedSettingsPreview(tab: .menus) }

struct FittedSettingsPreview: View {
    @StateObject private var fixture = PreviewFixture(theme: .glass)
    @StateObject private var loginItem = LoginItemManager()
    let tab: SettingsTab
    var body: some View {
        if tab == .general {
            GeneralSettingsContent(settings: fixture.settings, loginItem: loginItem,
                                   requestPermission: {}, openAppManagementSettings: {})
                .padding(SettingsWindowLayout.outerPadding).frame(width: SettingsWindowLayout.defaultWidth)
        } else {
            SettingsLayoutPreview(tab: tab, size: SettingsWindowLayout.fittedContentSize(settings: fixture.settings, loginItem: loginItem))
        }
    }
}

enum PreviewExport {
    @MainActor static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let verification = PreviewFixture(theme: .classic)
        try verification.verifyFocusSelection()
        try verification.verifySettingsRoundTrip()
        let delegate = AppDelegate(build: AppBuild(version: "preview", build: "1", fingerprint: "preview"),
                                   settings: verification.settings)
        try delegate.verifyClickExecutionForPreview()
        try ApplicationLaunchMonitor.verifyForPreview()
        try verifySettingsNavigation()
        try verifyGroupedWindowContent()
        try verifyScaledDragTargets()
        try verifyRegisteredViewport(to: directory)
        try OverlayChromeValidation.verify(to: directory)
        try verifyWebAppIcon()
        try verifyQuickOptionReopen()
        try verifyMenuCatalogChoices()
        let loginItem = LoginItemManager()
        let fittedSize = SettingsWindowLayout.fittedContentSize(settings: verification.settings, loginItem: loginItem)
        try verifySettingsWindowLayout(contentSize: fittedSize, settings: verification.settings, loginItem: loginItem, directory: directory)
        try save(RecentWindowExplanation().padding(20).frame(width: 548)
                    .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("recent-window-explanation.png"))
        try save(DeckPreview(theme: .classic, registeredCount: 18, realisticSample: true,
                             deliveredScale: true, keyboardFeedback: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("keyboard-execution-feedback.png"))
        try save(DeckPreview(theme: .classic, registeredCount: 18, realisticSample: true,
                             deliveredScale: true, launchFeedback: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("application-launch-feedback.png"))
        try save(GeneralSettingsContent(settings: verification.settings, loginItem: loginItem,
                                       requestPermission: {}, openAppManagementSettings: {})
                    .padding(SettingsWindowLayout.outerPadding)
                    .frame(width: fittedSize.width, height: fittedSize.height, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor)),
                 to: directory.appendingPathComponent("settings-general-fitted.png"))
        for size in [fittedSize, CGSize(width: 540, height: 638)] {
            for tab in [SettingsTab.general, .appearance, .menus, .registered] {
                try save(SettingsLayoutPreview(tab: tab, size: size).environment(\.colorScheme, .dark), titled: true,
                         to: directory.appendingPathComponent("settings-\(tab)-\(Int(size.width)).png"))
            }
        }
        try save(SettingsLayoutPreview(tab: .menus, size: fittedSize, emptyMenus: true)
                    .environment(\.colorScheme, .dark), to: directory.appendingPathComponent("settings-menus-empty.png"))
        try save(SettingsLayoutPreview(tab: .general, size: CGSize(width: 540, height: 638))
                    .environment(\.colorScheme, .dark), scrollToEnd: true,
                 to: directory.appendingPathComponent("settings-general-540-bottom.png"))
        try save(MenuAdditionPreview(size: MenuAdditionLayout.size(for: fittedSize))
                    .environment(\.colorScheme, .dark), to: directory.appendingPathComponent("menu-addition-large.png"))
        try save(MenuAdditionPreview(size: MenuAdditionLayout.size(for: CGSize(width: 540, height: 660)), manualExpanded: true)
                    .environment(\.colorScheme, .dark), to: directory.appendingPathComponent("menu-addition-compact.png"))
        let reopenPreview = PreviewFixture(theme: .glass)
        try save(OptionReopenSettings(settings: reopenPreview.settings).padding(20).frame(width: 570)
                    .background(Color(nsColor: .windowBackgroundColor)),
                 to: directory.appendingPathComponent("option-reopen-settings.png"))
        try verifySurfaceClipping(to: directory)
        try save(MenuUsagePreview().environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("menu-usage-dark.png"))
        for theme in DeckTheme.allCases {
            for dark in [false, true] {
                try save(AppearancePreview(theme: theme).environment(\.colorScheme, dark ? .dark : .light),
                         dark: dark, to: directory.appendingPathComponent("appearance-\(theme.rawValue)-\(dark ? "dark" : "light").png"))
                let view = DeckPreview(theme: theme).environment(\.colorScheme, dark ? .dark : .light)
                try save(view, dark: dark, to: directory.appendingPathComponent("\(theme.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
        try save(MonitorGroupingPreview(grouped: true, production: true, deliveredLayout: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("delivered-121-selected.png"))
        try save(DeckPreview(theme: .classic, customColors: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("custom-dark.png"))
        try save(DeckPreview(theme: .classic, compact: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("compact-dark.png"))
        for count in [0, 18, 36, 200] {
            try save(DeckPreview(theme: .classic, registeredCount: count).environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("profile-\(count).png"))
        }
        try save(DeckPreview(theme: .classic, registeredCount: 36, recentCount: 100).environment(\.colorScheme, .dark),
                 scrollToEnd: true, to: directory.appendingPathComponent("recent-scroll-bottom.png"))
        for (name, appearance): (String, RecentAppearance) in [("mixed", .mixedNeutral), ("squares-color", .squares), ("consecutive-small", .consecutiveSmall)] {
            try save(DeckPreview(theme: .classic, registeredCount: 18, recentAppearance: appearance, comparisonSample: true)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("recent-compare-\(name).png"))
        }
        for (name, appearance): (String, MenuAppearance) in [("pastel", .recentPastel), ("gray-square", .recentGraySquare)] {
            try save(DeckPreview(theme: .classic, registeredCount: 18, comparisonSample: true, menuAppearance: appearance)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("menu-compare-\(name).png"))
        }
        for (name, appearance): (String, MenuAppearance) in [("1-pastel-small", .recentPastel), ("2-gray-square", .recentGraySquare), ("3-original", .original)] {
            try save(DeckPreview(theme: .classic, registeredCount: 18, menuAppearance: appearance, realisticSample: true)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("menu-realistic-\(name).png"))
        }
        for (name, grouped, terminal): (String, Bool, Bool) in [
            ("current", false, false), ("grouped-active", true, false), ("grouped-terminal", true, true)
        ] {
            try save(MonitorGroupingPreview(grouped: grouped, terminalSelected: terminal)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("monitor-\(name).png"))
        }
        for (name, sizing): (String, MonitorPreviewSizing) in [
            ("visible-windows", .visibleWindows), ("active-app-only", .activeAppOnly)
        ] {
            try save(MonitorGroupingPreview(grouped: true, sizing: sizing)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("monitor-\(name).png"))
        }
        for terminal in [false, true] {
            try save(MonitorGroupingPreview(grouped: true, terminalSelected: terminal, production: true)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("grouped-production-\(terminal ? "terminal" : "chatgpt").png"))
        }
        for detail in [false, true] {
            try save(MonitorGroupingPreview(grouped: true, desktopColumns: true, detail: detail)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("desktop-columns-\(detail ? "full" : "overlay").png"))
            try save(MonitorGroupingPreview(grouped: true, detail: detail, threeColumns: true)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("desktop-three-columns-\(detail ? "full" : "overlay").png"))
            try save(MonitorGroupingPreview(grouped: true, detail: detail, threeColumns: true, squareColumnHeads: true)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("desktop-square-columns-\(detail ? "full" : "overlay").png"))
            try save(MonitorGroupingPreview(grouped: true, detail: detail, threeColumns: true, squareColumnHeads: true, largeIcons: true)
                        .environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("desktop-large-icons-\(detail ? "full" : "overlay").png"))
        }
        try save(MonitorGroupingPreview(grouped: true, detail: true, threeColumns: true, squareColumnHeads: true,
                                        largeIcons: true, relaxedSpacing: true)
                    .environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("desktop-spaced-icons-full.png"))
        try save(MonitorGroupingPreview(grouped: true, detail: true, threeColumns: true, squareColumnHeads: true,
                                        largeIcons: true, relaxedSpacing: true, fittedColumns: true)
                    .environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("desktop-fitted-columns-full.png"))
        let captionFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let threeCharacters = 8 + ("가나다" as NSString).size(withAttributes: [.font: captionFont]).width
        let fourCharacters = 8 + ("가나다라" as NSString).size(withAttributes: [.font: captionFont]).width
        guard threeCharacters <= 98.4 / 2, fourCharacters >= 98.4 / 2 else {
            throw NSError(domain: "TileLauncher.Preview", code: 81,
                          userInfo: [NSLocalizedDescriptionKey: "Start-style caption must reach the square tile midpoint between three and four Korean characters."])
        }
        print("Start-style caption: 3 Korean characters end at \(threeCharacters), 4 at \(fourCharacters), square midpoint=49.2; 1.4x preserves the ratio.")
        for enlarged in [false, true] {
            for canvas in [false, true] {
                try save(OverlayScalePreview(enlarged: enlarged, canvas: canvas).environment(\.colorScheme, .dark),
                         to: directory.appendingPathComponent("overlay-start-\(enlarged ? "large" : "base")-\(canvas ? "canvas" : "native").png"))
            }
        }
        for theme in DeckTheme.allCases {
            for dark in [false, true] {
                try save(DeckPreview(theme: theme, registeredCount: 18, realisticSample: true, deliveredScale: true)
                            .environment(\.colorScheme, dark ? .dark : .light), dark: dark,
                         to: directory.appendingPathComponent("delivered-121-\(theme.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
        for count in [0, 36, 200] {
            try save(DeckPreview(theme: .classic, registeredCount: count, deliveredScale: true).environment(\.colorScheme, .dark),
                     to: directory.appendingPathComponent("delivered-121-profile-\(count).png"))
        }
        try save(DeckPreview(theme: .classic, compact: true, registeredCount: 36, deliveredScale: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("delivered-121-small-screen.png"))
        try save(DeckPreview(theme: .classic, registeredCount: 36, recentCount: 100, deliveredScale: true).environment(\.colorScheme, .dark),
                 scrollToEnd: true, to: directory.appendingPathComponent("delivered-121-scroll-bottom.png"))
        // Native ColorPicker/radio controls don't export reliably from an unordered
        // window. Use the "모양 설정" Xcode canvas preview for those controls.
        print("Exported overlay/settings panes; unordered native tab controls and desktop Glass composition require separate visual checks.")
    }

    @MainActor private static func verifyScaledDragTargets() throws {
        let fixture = PreviewFixture(theme: .classic, registeredCount: 18)
        let layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                           cursor: .zero, scale: PanelLayout.preferredScale).fittingContent(registeredCount: 18)
        fixture.content.snapshot.layout = layout
        fixture.presentation.pin()
        let view = DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
            presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in }, selectMenu: { _, _, _ in },
            changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
            openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {}, dismiss: {})
        let hosting = NSHostingView(rootView: view)
        let surface = DeckSurfaceView(content: hosting, frame: CGRect(origin: .zero, size: layout.frame.size))
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        surface.layoutSubtreeIfNeeded()
        func dragViews(_ view: NSView) -> [OverlayDragHandle.DragView] {
            (view as? OverlayDragHandle.DragView).map { [$0] } ?? view.subviews.flatMap(dragViews)
        }
        guard let drag = dragViews(surface).first,
              abs(drag.bounds.width - layout.frame.width) < 1,
              abs(drag.bounds.height - DeckSpacing.header(compact: layout.compact, scale: layout.scale)) < 1,
              drag.excludedRects.count == 2,
              drag.excludedRects.allSatisfy({ abs($0.width - DeckSpacing.toolbarButton) < 1 && drag.bounds.contains($0) }),
              !window.isVisible else {
            throw NSError(domain: "TileLauncher.Preview", code: 82,
                          userInfo: [NSLocalizedDescriptionKey: "Scaled header/controls must use physical window coordinates."])
        }
        for rect in drag.excludedRects {
            let point = drag.convert(CGPoint(x: rect.midX, y: rect.midY), to: drag.superview)
            guard drag.hitTest(point) == nil else { throw NSError(domain: "TileLauncher.Preview", code: 83) }
        }
        let background = drag.convert(CGPoint(x: drag.bounds.midX, y: drag.bounds.midY), to: drag.superview)
        guard drag.hitTest(background) === drag else { throw NSError(domain: "TileLauncher.Preview", code: 84) }
        print("Scaled header: \(layout.frame.size), scale=\(layout.scale), physical drag bounds and both control exclusions passed offscreen.")
    }

    @MainActor private static func verifyRegisteredViewport(to directory: URL) throws {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        for size in [CGSize(width: 2560, height: 1056), CGSize(width: 1440, height: 876),
                     CGSize(width: 1280, height: 776), CGSize(width: 1024, height: 744)] {
            let fixture = PreviewFixture(theme: .classic, registeredCount: 39, recentCount: 14,
                                         menuComparison: true, realisticSample: true)
            fixture.settings.pins += (18..<39).map { index in
                let icon = PreviewIconAssets.app("TestApp\(index)", path: "/System/Applications/Notes.app")
                return PinnedItem(kind: .app, path: icon.path, bundleID: nil, name: "테스트 앱 \(index + 1)")
            }
            guard Set(fixture.settings.pins.map(\.id)).count == 39 else { throw NSError(domain: "TileLauncher.Preview", code: 100) }
            fixture.presentation.profile = fixture.settings.activeProfile
            var layout = PanelLayout.calculate(visibleFrame: CGRect(origin: .zero, size: size),
                cursor: .zero, scale: PanelLayout.preferredScale).fittingContent(registeredCount: 39)
            let snapshot = fixture.content.snapshot
            fixture.content.snapshot = OverlaySnapshot(context: snapshot.context, contextWindowTitle: snapshot.contextWindowTitle,
                apps: snapshot.apps, windows: Array(snapshot.windows.prefix(14)).enumerated().map { index, window in
                    var copy = window
                    copy.location = window.desktop == .current ? (index % 3 == 1 ? .otherVisibleDisplay : .activeDisplay)
                        : window.desktop == .other ? .hidden : .unknown
                    return copy
                }, layout: layout, permission: true, pins: fixture.settings.pins, profileID: "default",
                profileName: "기본", shortcuts: .registeredFirst, commands: [], frequentMenuIDs: [])
            layout = layout.fittingContent(registeredCount: 39, workRows: fixture.content.snapshot.workRows())
            fixture.content.snapshot.layout = layout
            let view = DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in }, selectMenu: { _, _, _ in },
                changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
                openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {}, dismiss: {})
            let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
            hosting.appearance = NSApp.appearance
            let surface = DeckSurfaceView(content: hosting, frame: CGRect(origin: .zero, size: layout.frame.size))
            let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSApp.appearance
            window.contentView = surface
            surface.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            surface.layoutSubtreeIfNeeded()
            func scrolls(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
            }
            print("Registered 39 / screen \(size) / panel \(layout.frame.size) / scale \(layout.scale)")
            guard let shelf = scrolls(surface).max(by: {
                $0.convert($0.bounds, to: hosting).minY < $1.convert($1.bounds, to: hosting).minY
            }), let document = shelf.documentView else { throw NSError(domain: "TileLauncher.Preview", code: 98) }
            let rect = shelf.convert(shelf.bounds, to: hosting)
            let bottomGap = layout.frame.height - rect.maxY
                - (DeckSpacing.footerBottom + DeckSpacing.footerTop + DeckSpacing.footerLine)
            guard document.frame.height <= shelf.contentView.bounds.height + 1,
                  abs(shelf.contentView.bounds.minY) < 1, bottomGap >= -2, bottomGap <= 8,
                  abs(rect.minX - DeckSpacing.edge) <= 1,
                  abs(rect.width - (layout.frame.width - 2 * DeckSpacing.edge)) <= 1,
                  !window.isVisible else {
                throw NSError(domain: "TileLauncher.Preview", code: 99,
                    userInfo: [NSLocalizedDescriptionKey: "Registered viewport: rect=\(rect), document=\(document.frame.size), viewport=\(shelf.contentView.bounds), blank=\(bottomGap)"])
            }
            let recent = scrolls(surface).filter { $0 !== shelf }.max { $0.bounds.width < $1.bounds.width }
            let tile = DeckGeometry(width: layout.contentSize.width, compact: layout.compact, scale: layout.scale)
            let visibleRows = recent.map { ($0.contentView.bounds.height + tile.gap) / (tile.unit + tile.gap) } ?? 0
            print("All 39 registered items fit: viewport \(shelf.contentView.bounds.size), document \(document.frame.size), unused bottom \(bottomGap); recent full rows=\(Int(visibleRows)), fraction=\(visibleRows)")
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.appearance?.performAsCurrentDrawingAppearance {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                }
                try bitmap.representation(using: .png, properties: [:])?.write(to:
                    directory.appendingPathComponent("registered-39-\(Int(size.width))-\(Int(size.height)).png"))
            }
            window.close()
        }
    }

    @MainActor private static func verifyGroupedWindowContent() throws {
        let fixture = PreviewFixture(theme: .classic)
        let terminal = AppItem(id: "test.terminal", pid: 1, name: "Terminal", url: nil)
        let safari = AppItem(id: "test.safari", pid: 2, name: "Safari", url: nil)
        let groups = [1, 2, 3, 1, 4, 2, 1, 1]
        let raw = groups.enumerated().map { index, group in
            WindowItem(id: UUID(), pid: pid_t(group), appName: "App", appURL: nil,
                       title: "Window \(index)", minimized: false, appID: "test.\(group == 1 ? "terminal" : group == 2 ? "safari" : String(group))",
                       desktop: index == 3 ? .other : .current)
        }
        let content = OverlayContent(OverlaySnapshot(context: terminal, contextWindowTitle: nil, apps: [], windows: [],
            layout: fixture.content.snapshot.layout, permission: true, pins: [], profileID: "default",
            profileName: "Preview", shortcuts: .registeredFirst, commands: []))
        content.refresh(context: terminal, apps: [terminal, safari], windows: raw,
                        trusted: true, commands: [], manualCount: 6)
        let frozen = content.snapshot
        guard frozen.windows.map(\.id) == Array(raw.prefix(6)).map(\.id),
              frozen.windows[1].id == raw[1].id else {
            throw NSError(domain: "TileLauncher.Preview", code: 80)
        }
        content.refresh(context: safari, apps: [terminal, safari], windows: raw,
                        trusted: true, commands: [], manualCount: nil)
        guard content.snapshot.windows.map(\.id) == raw.map(\.id),
              frozen.windows[1].id == raw[1].id,
              content.snapshot.windows[1].id == raw[1].id else {
            throw NSError(domain: "TileLauncher.Preview", code: 81)
        }
        print("Individual window MRU: shared numbered snapshot, manual limit, no app regrouping on app activation passed.")
    }

    @MainActor private static func verifySettingsWindowLayout(contentSize: CGSize, settings: SettingsStore, loginItem: LoginItemManager, directory: URL) throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        let navigation = SettingsNavigation()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, loginItem: loginItem,
            navigation: navigation, requestPermission: {}, openAppManagementSettings: {}, applicationProvider: { [] }))
        let largeScreen = CGRect(x: 0, y: 0, width: 1920, height: 1400)
        SettingsWindowLayout.apply(to: window, contentSize: contentSize, visibleFrame: largeScreen)
        guard window.contentLayoutRect.size == contentSize, contentSize.height < 1000,
              window.styleMask.contains(.resizable) else { throw NSError(domain: "TileLauncher.Preview", code: 76) }
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.contentView?.layoutSubtreeIfNeeded()
        func scrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        for scroll in scrolls(window.contentView!) {
            guard let document = scroll.documentView,
                  document.frame.height <= scroll.contentView.bounds.height + 1 else {
                throw NSError(domain: "TileLauncher.Preview", code: 95,
                              userInfo: [NSLocalizedDescriptionKey: "General settings require scrolling at the default size"])
            }
        }
        // No fixed frame around SettingsView: let the titled window move the
        // native tab selector into its title bar, exactly as production does.
        for tab in [SettingsTab.general, .appearance, .menus, .registered] {
            navigation.tab = tab
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            window.contentView?.layoutSubtreeIfNeeded()
            if tab == .general || tab == .appearance {
                for scroll in scrolls(window.contentView!) where !scroll.isHidden {
                    guard (scroll.documentView?.frame.height ?? 0) <= scroll.contentView.bounds.height + 1 else {
                        throw NSError(domain: "TileLauncher.Preview", code: 96)
                    }
                }
            }
            let frameView = window.contentView!.superview ?? window.contentView!
            if let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("settings-native-\(tab).png"))
            } else { throw NSError(domain: "TileLauncher.Preview", code: 97) }
        }
        window.setContentSize(CGSize(width: 800, height: 850))
        guard window.contentLayoutRect.width == 800 else { throw NSError(domain: "TileLauncher.Preview", code: 77) }
        SettingsWindowLayout.apply(to: window, contentSize: contentSize, visibleFrame: largeScreen)
        guard window.contentLayoutRect.size == contentSize else {
            throw NSError(domain: "TileLauncher.Preview", code: 78)
        }
        let smallScreen = CGRect(x: 0, y: 0, width: 1024, height: 768)
        SettingsWindowLayout.apply(to: window, contentSize: contentSize, visibleFrame: smallScreen)
        guard window.frame.width <= smallScreen.width - 48, window.frame.height <= smallScreen.height - 48,
              window.minSize.height <= window.frame.height, !window.isVisible else {
            throw NSError(domain: "TileLauncher.Preview", code: 79)
        }
        window.close()
        print("Settings window: General-fitted content \(contentSize), initial/reopen size, manual resizing and small-screen clamp passed offscreen.")
    }

    @MainActor private static func verifyMenuCatalogChoices() throws {
        let regular = [AvailableMenu(path: ["Finder", "Settings…"]),
                       AvailableMenu(path: ["File", "Apple", "Export"])]
        let apple = ["Apple", "", " APPLE "].flatMap { root in
            [["System Settings…"], ["Recent Items", "App.app"], ["Location", "Automatic"]].map {
                AvailableMenu(path: [root] + $0)
            }
        }
        let duplicate = AvailableMenu(path: ["File", "Export"])
        let filtered = MenuCatalog.searchableChoices(apple + regular + [duplicate, duplicate])
        guard filtered.map(\.id) == regular.map(\.id),
              MenuCatalog(initialChoices: apple).choices.isEmpty else {
            throw NSError(domain: "TileLauncher.Preview", code: 73)
        }
        for parent in [CGSize(width: 540, height: 660), CGSize(width: 580, height: 760), CGSize(width: 900, height: 1100)] {
            let size = MenuAdditionLayout.size(for: parent)
            guard size.width < parent.width, size.height < parent.height, size.height >= parent.height * 0.9,
                  size.height > 160 + 300 else { throw NSError(domain: "TileLauncher.Preview", code: 74) }
        }
        print("MenuCatalog: Apple and complete system subtrees excluded, real app names preserved, duplicates rejected; sheet follows parent height passed.")
    }

    @MainActor private static func verifyWebAppIcon() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tile-webapp-icon-\(UUID())")
        let bundle = directory.appendingPathComponent("Preview.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        icon.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); icon.unlockFocus()
        guard let data = icon.tiffRepresentation else { throw NSError(domain: "TileLauncher.Preview", code: 69) }
        try data.write(to: resources.appendingPathComponent("ApplicationIcon.tiff"))
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        var info = ["CFBundleIdentifier": "com.apple.Safari.WebApp.preview", "CFBundleIconFile": "ApplicationIcon.tiff"]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: infoURL)
        guard let loaded = AppIconCache.webAppIcon(bundle), loaded.size == icon.size,
              try Data(contentsOf: infoURL) == infoData else { throw NSError(domain: "TileLauncher.Preview", code: 70) }
        info["CFBundleIconFile"] = "../outside.tiff"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        guard AppIconCache.webAppIcon(bundle) != nil else { throw NSError(domain: "TileLauncher.Preview", code: 71) }
        info["CFBundleIdentifier"] = "preview.native"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        guard AppIconCache.webAppIcon(bundle) == nil else { throw NSError(domain: "TileLauncher.Preview", code: 72) }
        print("AppIconCache: direct Safari web-app resource loading without bundle changes, safe missing/traversal fallback and native-app separation passed.")
    }

    @MainActor private static func verifySettingsNavigation() throws {
        let navigation = SettingsNavigation()
        let app = AppItem(id: "preview.editor", pid: -1, name: "Preview Editor", url: nil)
        navigation.open(.addMenu, app: app)
        guard navigation.tab == .menus, navigation.menuAddition?.app == app else {
            throw NSError(domain: "TileLauncher.Preview", code: 65)
        }
        let first = navigation.menuAddition?.id
        navigation.open(.addMenu, app: app)
        guard navigation.menuAddition?.id != first else { throw NSError(domain: "TileLauncher.Preview", code: 66) }
        navigation.open(.registered, app: app)
        guard navigation.tab == .registered, navigation.menuAddition == nil else {
            throw NSError(domain: "TileLauncher.Preview", code: 67)
        }
        navigation.open(.general, app: nil)
        guard navigation.tab == .general, navigation.menuAddition == nil, navigation.preferredApp == nil else {
            throw NSError(domain: "TileLauncher.Preview", code: 68)
        }
        print("SettingsNavigation: General, Registered/Profile, current-app menu addition and repeated requests passed.")
    }

    @MainActor private static func verifyQuickOptionReopen() throws {
        // Synthetic NSEvents are passed directly to the production adapter.
        // No event monitor, OS input injection or visible panel is installed.
        let monitor = HoldMonitor()
        var memory = OptionReopenMemory<CGRect>()
        let frame = CGRect(x: -900, y: 80, width: 800, height: 650)
        var quick = 0, ordinary = 0, executions = 0
        var actionPending = false
        monitor.canTriggerHold = { true }
        monitor.hasPressedMouseButtons = { false }
        monitor.onReopenCancelled = { memory.cancel() }
        monitor.onShow = { ordinary += 1; monitor.isShowing = true }
        monitor.onHide = { reason, time in
            memory.record(frame, at: time, reason: reason, held: monitor.isShowing, actionPending: actionPending)
            monitor.isShowing = false
        }
        monitor.onRelease = {
            if actionPending { executions += 1; actionPending = false }
        }
        monitor.onQuickReopen = { time in
            guard memory.take(at: time) == frame else { return false }
            quick += 1; monitor.isShowing = true
            return true
        }
        defer {
            monitor.stop()
            monitor.onShow = nil; monitor.onHide = nil; monitor.onQuickReopen = nil
        }
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, _ time: TimeInterval) throws {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                              timestamp: time, windowNumber: 0, context: nil,
                                              characters: "", charactersIgnoringModifiers: "",
                                              isARepeat: false, keyCode: type == .flagsChanged ? 58 : 0) else {
                throw NSError(domain: "TileLauncher.Preview", code: 40)
            }
            _ = monitor.handle(event, external: true)
        }
        memory.record(frame, at: 10, reason: .release, held: true, actionPending: false)
        try event(.flagsChanged, .option, 10.55)
        guard quick == 1, ordinary == 0, monitor.isShowing else { throw NSError(domain: "TileLauncher.Preview", code: 41) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard ordinary == 0 else { throw NSError(domain: "TileLauncher.Preview", code: 42) }
        try event(.flagsChanged, [], 11)
        try event(.keyDown, [], 11.01)
        try event(.flagsChanged, .option, 11.1)
        guard quick == 1, ordinary == 0 else { throw NSError(domain: "TileLauncher.Preview", code: 43) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard ordinary == 1 else { throw NSError(domain: "TileLauncher.Preview", code: 44) }
        actionPending = true
        try event(.flagsChanged, [], 12)
        try event(.flagsChanged, .option, 12.1)
        guard executions == 1, quick == 1 else { throw NSError(domain: "TileLauncher.Preview", code: 45) }
        print("HoldMonitor: immediate same-location recovery, no duplicate timer, intervening input cancellation, normal delay and single action release passed.")
    }

    @MainActor private static func verifySurfaceClipping(to directory: URL) throws {
        // A bright, rectangular descendant deliberately fills every corner. The
        // production surface must clip it, including after its bounds change.
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemBlue.cgColor
        let surface = DeckSurfaceView(content: content, frame: CGRect(x: 0, y: 0, width: 512, height: 420))
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = surface
        defer { window.contentView = nil; window.close() }
        for size in [CGSize(width: 512, height: 420), CGSize(width: 1040, height: 720)] {
            window.setContentSize(size)
            surface.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            surface.layoutSubtreeIfNeeded()
            surface.layer?.displayIfNeeded()
            guard content.convert(content.bounds, to: surface) == surface.bounds else {
                throw NSError(domain: "TileLauncher.Preview", code: 35,
                              userInfo: [NSLocalizedDescriptionKey: "Glass overscan changed content bounds"])
            }
            for scale in [1, 2] {
                let width = Int(size.width) * scale, height = Int(size.height) * scale
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw NSError(domain: "TileLauncher.Preview", code: 30)
                }
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                surface.layer?.render(in: context)
                guard let image = context.makeImage(), let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
                    throw NSError(domain: "TileLauncher.Preview", code: 31)
                }
                let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
                for (x, y) in corners {
                    let dx = x == 0 ? 1 : -1, dy = y == 0 ? 1 : -1
                    for offsetX in 0..<(5 * scale) {
                        for offsetY in 0..<(5 * scale) {
                            guard bytes[((y + offsetY * dy) * width + x + offsetX * dx) * 4 + 3] == 0 else {
                                throw NSError(domain: "TileLauncher.Preview", code: 32,
                                              userInfo: [NSLocalizedDescriptionKey: "Panel corner leaked at \(size), \(scale)x"])
                            }
                        }
                    }
                }
                guard bytes[((height / 2) * width + width / 2) * 4 + 3] > 240 else {
                    throw NSError(domain: "TileLauncher.Preview", code: 33)
                }
                let bitmap = NSBitmapImageRep(cgImage: image)
                try bitmap.representation(using: .png, properties: [:])?.write(to:
                    directory.appendingPathComponent("surface-\(Int(size.width))-\(scale)x.png"))
            }
        }
        guard !window.isVisible else { throw NSError(domain: "TileLauncher.Preview", code: 34) }
        print("Panel surface: all four corners transparent at 1x/2x, fill preserved, resize covered; never shown onscreen.")
    }
    @MainActor static func save<V: View>(_ view: V, dark: Bool = true, scrollToEnd: Bool = false, titled: Bool = false, to url: URL) throws {
        // AppKit hosts render native controls/scroll views that ImageRenderer omits.
        // This window is never ordered onscreen and never becomes key.
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSApp.appearance
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: titled ? [.titled, .closable, .miniaturizable, .resizable] : .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        if scrollToEnd {
            func scrollViews(in view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
            }
            guard let scroll = scrollViews(in: hosting).first(where: {
                ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1
            }), let document = scroll.documentView else {
                throw NSError(domain: "TileLauncher.Preview", code: 75,
                              userInfo: [NSLocalizedDescriptionKey: "Preview has no usable overflow scroll view: \(url.lastPathComponent)"])
            }
            let end = document.isFlipped ? document.frame.height - scroll.contentView.bounds.height : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: end))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
            print("Offscreen scroll view reaches the bottom: \(url.lastPathComponent)")
        }
        let captureRect = hosting.bounds
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: captureRect) else {
            throw NSError(domain: "TileLauncher.Preview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render \(url.lastPathComponent)"])
        }
        hosting.appearance?.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: captureRect, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TileLauncher.Preview", code: 2)
        }
        try png.write(to: url)
        window.contentView = nil
        window.close()
    }
}
