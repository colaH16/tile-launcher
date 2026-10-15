import AppKit
import SwiftUI
import DeckCore

/// Offscreen, synthetic validation of the adopted R180 layout.
enum OverlayChromeValidation {
    @MainActor static func verify(to directory: URL) throws {
        let fixture = PreviewFixture(theme: .classic, registeredCount: 39,
                                     menuComparison: true, realisticSample: true)
        fixture.settings.pins += (18..<39).map { index in
            let icon = PreviewIconAssets.app("HeightTest\(index)", path: "/System/Applications/Notes.app")
            return PinnedItem(kind: .app, path: icon.path, bundleID: nil, name: "등록 앱 \(index + 1)")
        }
        fixture.presentation.profile = fixture.settings.activeProfile
        fixture.presentation.pin()
        let snapshot = fixture.content.snapshot
        var layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1056),
                                           cursor: .zero, scale: PanelLayout.preferredScale)
        fixture.content.snapshot = OverlaySnapshot(context: snapshot.context,
            contextWindowTitle: snapshot.contextWindowTitle, apps: snapshot.apps,
            windows: snapshot.windows.enumerated().map { index, window in
                var copy = window
                copy.location = window.desktop == .current ? (index % 3 == 1 ? .otherVisibleDisplay : .activeDisplay)
                    : window.desktop == .other ? .hidden : .unknown
                return copy
            }, layout: layout, permission: true, pins: fixture.settings.pins, profileID: "default",
            profileName: "기본", shortcuts: .registeredFirst, commands: snapshot.commands,
            frequentMenuIDs: snapshot.frequentMenuIDs)
        layout = layout.fittingContent(registeredCount: 39, workRows: fixture.content.snapshot.workRows())
        guard layout.frame.size == CGSize(width: 1568, height: 918) else {
            throw NSError(domain: "TileLauncher.Preview", code: 101,
                          userInfo: [NSLocalizedDescriptionKey: "Adopted layout changed: \(layout.frame.size)"])
        }
        fixture.content.snapshot.layout = layout
        let view = DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
            presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in }, selectMenu: { _, _, _ in },
            changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
            openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {}, dismiss: {})
            .frame(width: layout.frame.width, height: layout.frame.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DeckSurfaceView.cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
        try PreviewExport.save(view, to: directory.appendingPathComponent("adopted-143.png"))
        // Light/dark rendering of the same sample: chosen symbol → shortcut → text menu tiles.
        let glyphs = DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
            presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in }, selectMenu: { _, _, _ in },
            changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
            openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {}, dismiss: {})
            .frame(width: layout.frame.width, height: layout.frame.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DeckSurfaceView.cornerRadius, style: .continuous))
        try PreviewExport.save(glyphs.environment(\.colorScheme, .light), dark: false,
                               to: directory.appendingPathComponent("menu-glyphs-light.png"))
        // R192: a Handoff offer replaces the first recent tile at the same size.
        let before = fixture.content.snapshot
        let handoff = HandoffItem(appName: "Safari", appURL: PreviewIconAssets.app("Safari", path: "/Applications/Safari.app"),
                                  device: "com.apple.iphone-15-pro-1")
        let app = AppItem(id: "test.editor", pid: 123, name: "Editor", url: nil)
        let current = WindowItem(id: UUID(), pid: 123, appName: "Editor", appURL: nil, title: "Document A", minimized: false, appID: app.id)
        let previous = WindowItem(id: UUID(), pid: 123, appName: "Editor", appURL: nil, title: "Document B", minimized: false, appID: app.id)
        let probe = OverlayContent(before)
        probe.refresh(context: app, apps: [app], windows: [current, previous], trusted: true, commands: [], manualCount: nil, handoff: handoff)
        guard probe.snapshot.windows.first?.handoff != nil, probe.snapshot.menuContextWindow?.id == current.id,
              probe.snapshot.windows.first(where: { $0.pid == app.pid })?.id == previous.id else {
            throw NSError(domain: "TileLauncher.Preview", code: 103,
                          userInfo: [NSLocalizedDescriptionKey: "Handoff altered the menu's source document"])
        }
        probe.refresh(context: app, apps: [app], windows: [previous], trusted: true, commands: [], manualCount: nil, handoff: nil)
        guard probe.snapshot.menuContextWindow?.id == previous.id else { throw NSError(domain: "TileLauncher.Preview", code: 104) }
        print("Handoff display replacement preserves Document A as the menu action context; later window changes update it.")
        fixture.content.snapshot = OverlaySnapshot(context: before.context, contextWindowTitle: before.contextWindowTitle,
            apps: before.apps, windows: OverlayContent.applyHandoff(handoff, to: before.windows), layout: before.layout,
            permission: true, pins: before.pins, profileID: before.profileID, profileName: before.profileName,
            shortcuts: before.shortcuts, commands: before.commands, frequentMenuIDs: before.frequentMenuIDs)
        guard fixture.content.snapshot.workRows() == before.workRows(),
              fixture.content.snapshot.windows.count == before.windows.count else {
            throw NSError(domain: "TileLauncher.Preview", code: 102,
                          userInfo: [NSLocalizedDescriptionKey: "Handoff tile changed the recent layout"])
        }
        try PreviewExport.save(view, to: directory.appendingPathComponent("handoff-tile.png"))
        fixture.content.snapshot = before
        let titles = VStack(spacing: 16) {
            OverlayTitleView(iconURL: snapshot.windows.first?.appURL, appName: "Finder", windowName: "Downloads")
            OverlayTitleView(iconURL: snapshot.windows.first?.appURL,
                             appName: "아주 긴 애플리케이션 이름과 작업 환경", windowName: "작업 자료 — 긴 창 이름의 줄임 표시 확인")
            OverlayTitleView(iconURL: PreviewIconAssets.folder("작업 폴더").url, appName: "작업 폴더", windowName: "")
        }.frame(width: 336).padding(16).background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        try PreviewExport.save(titles, to: directory.appendingPathComponent("header-long-and-folder.png"))
        print("Adopted chrome: 1568×918, 39 registered items, tile scale 1.4, independent title/footer sizes.")
    }
}
