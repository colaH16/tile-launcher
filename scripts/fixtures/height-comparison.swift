import AppKit
import SwiftUI
import DeckCore

// R180: injected into isolated historical/current checkouts by the renderer.
// No production UI or live app/window inventory is used.
enum ScaleHeightExport {
    @MainActor static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        for (name, scale) in /*CASES*/ {
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
                                               cursor: .zero, scale: scale).fittingContent(registeredCount: 39)
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
            /*FIT_CURRENT*/
            fixture.content.snapshot.layout = layout
            let view = DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                presentation: fixture.presentation, selectApp: { _ in }, selectPin: { _ in }, selectMenu: { _, _, _ in },
                changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
                openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {},
                /*CHROME*/ dismiss: {})
                .frame(width: layout.frame.width, height: layout.frame.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: /*RADIUS*/, style: .continuous))
                .environment(\.colorScheme, .dark)
            try save(view, size: layout.frame.size, name: name, directory: directory)
            print("R180 \(name): scale=\(layout.scale), panel=\(layout.frame.size), pins=\(fixture.settings.pins.count), windows=\(snapshot.windows.count), menus=\(snapshot.commands.count)")
        }
    }
    @MainActor static func save<V: View>(_ view: V, size: CGSize, name: String, directory: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSApp.appearance
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSApp.appearance
        window.contentView = hosting; hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        func scrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        let geometry = scrolls(hosting).map { scroll -> [String: CGFloat] in
            let bounds = scroll.convert(scroll.bounds, to: hosting)
            return ["x": bounds.minX, "y": bounds.minY, "viewport": scroll.contentView.bounds.height,
                    "document": scroll.documentView?.frame.height ?? 0, "width": scroll.bounds.width]
        }
        let metadata: [String: Any] = ["name": name, "width": size.width, "height": size.height, "scrolls": geometry]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(name).json"))
        let strips: [(String, CGRect)] = [
            ("full", hosting.bounds),
            ("left", CGRect(x: 0, y: 0, width: 220, height: size.height)),
            ("center", CGRect(x: (size.width - 220) / 2, y: 0, width: 220, height: size.height)),
            ("right", CGRect(x: size.width - 220, y: 0, width: 220, height: size.height))
        ]
        for (part, rect) in strips {
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: rect) else { fatalError("Missing bitmap") }
            hosting.appearance?.performAsCurrentDrawingAppearance { hosting.cacheDisplay(in: rect, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])!
                .write(to: directory.appendingPathComponent("\(name)-\(part).png"))
        }
        window.contentView = nil; window.close()
    }
}
