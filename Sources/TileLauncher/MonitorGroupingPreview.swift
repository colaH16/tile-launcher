import AppKit
import SwiftUI
import DeckCore

/// R142: screenshot-inspired synthetic samples, never a live inventory or setting.
enum MonitorPreviewSizing {
    case smallFollowers, visibleWindows, activeAppOnly
}

struct MonitorGroupingPreview: View {
    @StateObject private var fixture: PreviewFixture
    private let sizes: [RecentTileSize]?
    private let emphasized: Set<UUID>?
    private let grouped: Bool
    private let production: Bool
    private let columns: DesktopColumnsPreviewData?
    private let detail: Bool
    private let largeIcons: Bool
    private let relaxedSpacing: Bool

    init(grouped: Bool, terminalSelected: Bool = false, sizing: MonitorPreviewSizing = .smallFollowers,
         production: Bool = false, desktopColumns: Bool = false, detail: Bool = false,
         threeColumns: Bool = false, squareColumnHeads: Bool = false, largeIcons: Bool = false,
         relaxedSpacing: Bool = false, fittedColumns: Bool = false) {
        self.grouped = grouped
        self.production = production
        self.detail = detail
        self.largeIcons = largeIcons
        self.relaxedSpacing = relaxedSpacing
        let fixture = PreviewFixture(theme: .classic, registeredCount: 18, realisticSample: true)
        fixture.settings.tileColors.menus = TileColor(0x4CBB00)
        fixture.settings.tileColors.windows = TileColor(0x2FA3E7)
        fixture.settings.tileColors.registered = TileColor(0xB793FD)
        let existing = Dictionary(fixture.content.snapshot.windows.compactMap { window in
            window.appURL.map { (window.appName, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let bundleIDs = ["Safari Technology Preview": "com.apple.SafariTechnologyPreview",
                         "Notes": "com.apple.Notes", "Notes Web": "com.apple.Safari.WebApp.9BE19782-1A42-4264-9783-43E76166FD57",
                         "Ulanzi Studio": "com.ulanzi.studio", "Microsoft Excel": "com.microsoft.Excel",
                         "Microsoft PowerPoint": "com.microsoft.Powerpoint", "Aside": "at.studio.AsideBrowser",
                         "USBclean": "com.sweetpproductions.USBclean", "Developer": "developer.apple.wwdc-Release",
                         "Xcode": "com.apple.dt.Xcode"]
        var icons = existing
        for (name, bundleID) in bundleIDs {
            let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path ?? "/Preview/Missing.app"
            icons[name] = PreviewIconAssets.app(name, path: path)
        }
        // Monitor A is shown in the supplied Mission Control image. B assignments
        // are inferred from the earlier overlay's visible-desktop color, not measured.
        let samples: [(String, String, String, Bool)] = [
            ("ChatGPT", "ChatGPT", "A", false),
            ("Safari Technology Preview", "블로그 게시 상태", "A", false),
            ("Safari Technology Preview", "Personal — 홈", "B", false),
            ("iTerm2", "블로그 작업", "B", false),
            ("CotEditor", "Untitled", "A", false),
            ("Finder", "프로젝트 자료", "A", false),
            ("Docmost", "프로젝트 칸반", "other", false),
            ("Notes", "Quick Notes — 34 notes", "A", false),
            ("Docmost", "이번 주 작업", "B", false),
            ("Ulanzi Studio", "", "none", true),
            ("Microsoft Excel", "", "none", true),
            ("Microsoft PowerPoint", "", "none", true),
            ("iTerm2", "[8-zbm] ~", "B", false),
            ("ChatGPT", "ChatGPT", "other", false),
            ("Aside", "", "none", true),
            ("USBclean", "", "none", true),
            ("Claude", "다른 데스크탑의 창", "other", false),
            ("Claude", "설계 메모", "other", false),
            ("Claude", "회의 기록", "other", false),
            ("Notes Web", "", "none", true),
            ("Xcode", "", "none", true),
            ("Developer", "", "none", true),
            ("Finder", "Downloads", "A", false)
        ]
        let names = Array(Set(samples.map { $0.0 })).sorted()
        var windows = samples.map { item in
            WindowItem(id: UUID(), pid: Int32(names.firstIndex(of: item.0)! + 100),
                       appName: item.0, appURL: icons[item.0], title: item.1, minimized: false,
                       desktop: item.2 == "none" ? .unknown : item.2 == "other" ? .other : .current,
                       isApplication: item.3)
        }
        let monitor = Dictionary(uniqueKeysWithValues: zip(windows.map(\.id), samples.map { $0.2 }))
        let activeMonitor = terminalSelected ? "B" : "A"
        if grouped {
            var appOrder: [pid_t] = []
            if terminalSelected { appOrder.append(windows.first { $0.appName == "iTerm2" }!.pid) }
            for window in windows where !appOrder.contains(window.pid) { appOrder.append(window.pid) }
            windows = appOrder.flatMap { pid in windows.filter { $0.pid == pid } }
        }
        // Size depends on the active monitor; color independently follows all
        // visible desktops, including small subsequent windows in a group.
        emphasized = grouped ? Set(windows.filter {
            !$0.isApplication && $0.desktop == .current
        }.map(\.id)) : nil
        let contextName = terminalSelected ? "iTerm2" : "ChatGPT"
        let conventionalSizes: [RecentTileSize]? = grouped ? windows.indices.map { index in
            let window = windows[index]
            let firstWindow = index == 0 || windows[index - 1].pid != window.pid
            if window.isApplication { return .application }
            switch sizing {
            case .smallFollowers:
                if !firstWindow { return .application }
                return monitor[window.id] == activeMonitor ? .wide : .square
            case .visibleWindows:
                if window.desktop != .current { return .application }
                return firstWindow && monitor[window.id] == activeMonitor ? .wide : .square
            case .activeAppOnly:
                if window.desktop != .current { return .application }
                return firstWindow && window.appName == contextName ? .wide : .square
            }
        } : nil
        if desktopColumns || threeColumns {
            func groups(matching predicate: (WindowItem) -> Bool) -> [[Int]] {
                var keys: [String] = []
                let indices = windows.indices.filter { !windows[$0].isApplication && predicate(windows[$0]) }
                for index in indices where !keys.contains(windows[index].appKey) { keys.append(windows[index].appKey) }
                return keys.map { key in indices.filter { windows[$0].appKey == key } }
            }
            let visible = groups { $0.desktop == .current }, other = groups { $0.desktop != .current }
            let applications = windows.indices.filter { windows[$0].isApplication }
            let lanes: [DesktopColumnsPreviewData.Column]
            if threeColumns {
                lanes = [
                    .init(title: "현재 데스크탑", modules: squareColumnHeads ? 4 : 5,
                          groups: groups { $0.desktop == .current && monitor[$0.id] == activeMonitor }),
                    .init(title: "다른 모니터 · 보임", modules: squareColumnHeads ? 4 : 3,
                          groups: groups { $0.desktop == .current && monitor[$0.id] != activeMonitor }),
                    .init(title: "보이지 않는 데스크탑", modules: 3, groups: other, applications: applications)
                ]
            } else {
                lanes = [.init(title: "보이는 데스크탑", modules: 6, groups: visible),
                         .init(title: "다른 데스크탑", modules: 6, groups: other, applications: applications)]
            }
            var columnSizes = Array(repeating: RecentTileSize.application, count: windows.count)
            for lane in lanes {
                for group in lane.groups {
                    if let first = group.first {
                        columnSizes[first] = !squareColumnHeads && monitor[windows[first].id] == activeMonitor ? .wide : .square
                    }
                }
            }
            let all = lanes.flatMap { $0.groups.flatMap { $0 } + $0.applications }
            precondition(Set(all) == Set(windows.indices) && all.count == windows.count)
            // Each column top-to-bottom, then the next column to the right.
            let remap = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element, $0.offset) })
            windows = all.map { windows[$0] }
            sizes = all.map { columnSizes[$0] }
            let mapped = lanes.map { lane in
                DesktopColumnsPreviewData.Column(title: lane.title, modules: lane.modules,
                    groups: lane.groups.map { $0.map { remap[$0]! } }, applications: lane.applications.map { remap[$0]! })
            }
            if threeColumns {
                var data = DesktopColumnsPreviewData(columns: mapped, referenceModules: 12)
                data.relaxedSpacing = relaxedSpacing
                if fittedColumns {
                    let geometry = DeckGeometry(width: fixture.content.snapshot.layout.frame.width, compact: false)
                    data = data.fittingGroups(sizes: sizes!, module: (geometry.unit - geometry.gap) / 2)
                    print("Fitted desktop columns: \(data.columns.map(\.modules)), width=\(data.preferredWidth!), module=\(data.fixedModule!)")
                }
                columns = data
            } else {
                columns = DesktopColumnsPreviewData(visible: mapped[0].groups, other: mapped[1].groups,
                                                     applications: mapped[1].applications)
            }
            print("Desktop columns \(lanes.map(\.modules)): \(lanes.map { $0.groups.count }) groups, \(lanes.map { $0.groups.flatMap { $0 }.count }) windows, applications=\(applications.count); all \(all.count) indices preserved")
        } else {
            columns = nil
            sizes = conventionalSizes
        }
        if let sizes, sizing != .smallFollowers {
            print("Monitor sizing \(sizing): wide=\(sizes.filter { $0 == .wide }.count), square=\(sizes.filter { $0 == .square }.count), small=\(sizes.filter { $0 == .application }.count)")
        }
        let context = AppItem(id: "preview.monitor.context", pid: -1, name: contextName, url: icons[contextName])
        var command = MenuCommand(appID: context.id, appName: context.name, path: ["File", "New Window"])
        for _ in 0..<4 { command.recordUse(at: Date()) }
        fixture.settings.commands = [command]
        fixture.content.snapshot = OverlaySnapshot(context: context, contextWindowTitle: contextName,
            apps: [context], windows: windows, layout: fixture.content.snapshot.layout, permission: true,
            pins: fixture.settings.pins, profileID: "default", profileName: "오마",
            shortcuts: .registeredFirst, commands: [command])
        fixture.presentation.windowDesktops = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.desktop) })
        fixture.presentation.profile = LauncherProfile(id: "default", name: "오마", items: fixture.settings.pins)
        _fixture = StateObject(wrappedValue: fixture)
    }

    private var deck: DeckView {
        DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                 presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in },
                 selectMenu: { _, _, _ in }, changeProfile: { _ in }, cycleProfile: { _ in },
                 selectWindow: { _ in }, openURL: { _ in }, openInFinder: { _ in }, openTrash: {},
                 showSettings: { _ in }, requestPermission: {}, pinOverlay: {},
                 recentAppearance: production ? .grouped : .consecutiveSmall,
                 previewWindowSizes: production ? nil : sizes,
                 previewEmphasizedWindows: production ? nil : emphasized,
                 previewRecentLegend: production ? nil : grouped ? "현재 보이는 데스크탑" : nil,
                 previewDesktopColumns: columns, previewLargeWindowIcons: largeIcons,
                 previewBalancedWindowLabels: relaxedSpacing, dismiss: {})
    }

    var body: some View {
        if detail {
            deck.desktopColumnDetails.padding(24)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            deck
            .frame(width: fixture.content.snapshot.layout.frame.width, height: fixture.content.snapshot.layout.frame.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(DeckSurfaceView.shape)
        }
    }
}
