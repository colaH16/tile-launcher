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
