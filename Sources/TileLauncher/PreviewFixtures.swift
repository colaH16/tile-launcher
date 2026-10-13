import AppKit
import SwiftUI
import DeckCore

/// Synthetic data only: no AX observer, keyboard monitor, real folder or user settings.
final class PreviewFixture: ObservableObject {
    let settings: SettingsStore
    let content: OverlayContent
    let presentation = OverlayPresentation()
    let browser = FolderBrowser()
    private let suite: String
    private let defaults: UserDefaults
    init(theme: DeckTheme, customColors: Bool = false, compact: Bool = false) {
        suite = "dev.cola16.TileLauncher.preview.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults)
        settings.theme = theme
        if customColors {
            settings.tileColors.menus = TileColor(0xAA4725)
            settings.tileColors.windows = TileColor(0x7651AA)
            settings.tileColors.registered = TileColor(0x297D76)
        }
        let pins = (1...35).map { PinnedItem(kind: .app, path: "/Preview/App\($0).app", bundleID: nil, name: "앱 \($0)") }
        settings.pins = pins
        let app = AppItem(id: "preview.editor", pid: -1, name: "문서 편집기", url: nil)
        var commands = [
            MenuCommand(appID: app.id, appName: app.name, path: ["파일", "PDF로 내보내기"]),
            MenuCommand(appID: app.id, appName: app.name, path: ["도구", "그림 크기 줄이기"]),
            MenuCommand(appID: app.id, appName: app.name, path: ["파일", "저장"], isPinned: false),
            MenuCommand(appID: app.id, appName: app.name, path: ["이동", "폴더로 이동…"], isPinned: false),
            MenuCommand(appID: app.id, appName: app.name, path: ["보기", "확대"], isPinned: false)
        ]
        for _ in 0..<4 { commands[2].recordUse(at: Date()) }
        commands[3].recordUse(at: Date())
        settings.commands = commands
        var windows: [WindowItem] = []
        for index in 0..<16 {
            let pid: pid_t = index < 2 ? 1 : Int32(index)
            let name = index < 2 ? "Terminal" : "앱 \(index + 1)"
            let title = index == 0 ? "cc2" : (index == 1 ? "se3" : "프로젝트 문서 \(index + 1)")
            let desktop: WindowDesktop = index < 4 ? .current : .other
            windows.append(WindowItem(id: UUID(), pid: pid, appName: name, appURL: nil,
                                      title: title, minimized: false, desktop: desktop))
        }
        let layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: compact ? 560 : 1440,
                                                                height: compact ? 468 : 1000),
                                           cursor: CGPoint(x: 720, y: 500)).fittingContent(registeredCount: pins.count)
        content = OverlayContent(OverlaySnapshot(context: app, contextWindowTitle: "미리보기 문서",
                    apps: [app], windows: windows, layout: layout, permission: true, pins: pins,
                    profileID: "default", profileName: "기본", shortcuts: .registeredFirst, commands: commands,
                    frequentMenuIDs: MenuCommand.frequentIDs(commands, appID: app.id)))
        presentation.profile = settings.activeProfile
        presentation.windowDesktops = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
        // Keep the synthetic panel unpinned, so its drag representable cannot affect a preview host window.
    }
    deinit { defaults.removePersistentDomain(forName: suite) }
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
        settings.tileColors.menus = TileColor(0xCC7722)
        settings.tileColors.windows = TileColor(0x7766BB)
        settings.tileColors.registered = TileColor(0x448877)
        let expectedColors = settings.tileColors
        settings.theme = .glass
        settings.menuHistory = MenuHistoryPreferences(recentDays: 45, frequentDays: 120)
        let restored = SettingsStore(defaults: defaults)
        guard restored.tileColors == expectedColors, restored.theme == .glass,
              restored.menuHistory == settings.menuHistory,
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
    }
}

struct DeckPreview: View {
    @StateObject var fixture: PreviewFixture
    init(theme: DeckTheme, customColors: Bool = false, compact: Bool = false) {
        _fixture = StateObject(wrappedValue: PreviewFixture(theme: theme, customColors: customColors, compact: compact))
    }
    var body: some View {
        DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                 presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in },
                 selectMenu: { _, _, _ in }, changeProfile: { _ in }, cycleProfile: { _ in },
                 selectWindow: { _ in }, openURL: { _ in }, openInFinder: { _ in }, openTrash: {},
                 showSettings: {}, requestPermission: {}, pinOverlay: {}, dismiss: {})
            .frame(width: fixture.content.snapshot.layout.frame.width, height: fixture.content.snapshot.layout.frame.height)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct AppearancePreview: View {
    @StateObject private var fixture = PreviewFixture(theme: .classic)
    var body: some View { AppearanceView(settings: fixture.settings).frame(width: 580, height: 760) }
}

#Preview("클래식 · 기본색") { DeckPreview(theme: .classic).preferredColorScheme(.dark) }
#Preview("유리 · 기본색") { DeckPreview(theme: .glass).preferredColorScheme(.dark) }
#Preview("사용자 색 · 밝은 화면") { DeckPreview(theme: .classic, customColors: true).preferredColorScheme(.light) }
#Preview("모양 설정") { AppearancePreview() }

enum PreviewExport {
    @MainActor static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PreviewFixture(theme: .classic).verifySettingsRoundTrip()
        for theme in DeckTheme.allCases {
            for dark in [false, true] {
                let view = DeckPreview(theme: theme).environment(\.colorScheme, dark ? .dark : .light)
                try save(view, dark: dark, to: directory.appendingPathComponent("\(theme.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
        try save(DeckPreview(theme: .classic, customColors: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("custom-dark.png"))
        try save(DeckPreview(theme: .classic, compact: true).environment(\.colorScheme, .dark),
                 to: directory.appendingPathComponent("compact-dark.png"))
        // Native ColorPicker/radio controls don't export reliably from an unordered
        // window. Use the "모양 설정" Xcode canvas preview for those controls.
        print("Exported tile layout/color samples; native settings controls and desktop Glass composition are not covered.")
    }
    @MainActor private static func save<V: View>(_ view: V, dark: Bool = true, to url: URL) throws {
        // AppKit hosts render native controls/scroll views that ImageRenderer omits.
        // This window is never ordered onscreen and never becomes key.
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSApp.appearance
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "TileLauncher.Preview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render \(url.lastPathComponent)"])
        }
        hosting.appearance?.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TileLauncher.Preview", code: 2)
        }
        try png.write(to: url)
        window.contentView = nil
        window.close()
    }
}
