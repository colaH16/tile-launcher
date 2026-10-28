#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import DeckCore

/// Uses synthetic settings and injected image readers, never installed apps.
enum IconReadAheadValidation {
    private final class Reads {
        private let lock = NSLock()
        private var apps = Set<String>(), menus = Set<String>()
        private var calls = 0
        func hasApp(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return apps.contains(url.path) }
        func hasMenu(_ icon: MenuResourceIcon) -> Bool { lock.lock(); defer { lock.unlock() }; return menus.contains(icon.digest) }
        func app(_ url: URL) { lock.lock(); apps.insert(url.path); calls += 1; lock.unlock() }
        func menu(_ icon: MenuResourceIcon) { lock.lock(); menus.insert(icon.digest); calls += 1; lock.unlock() }
        func evict() { lock.lock(); apps.removeAll(); menus.removeAll(); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    }
    @MainActor static func verify() throws {
        let fixture = PreviewFixture(theme: .classic, registeredCount: 0)
        let settings = fixture.settings
        settings.commands = []
        let reads = Reads()
        let preloader = IconReadAhead(settings: settings, hasApp: reads.hasApp, readApp: reads.app,
                                     hasMenu: reads.hasMenu, readMenu: reads.menu)
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw NSError(domain: "TileLauncher.IconReadAhead", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait(_ condition: () -> Bool) throws {
            let end = Date().addingTimeInterval(2)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            try check(condition(), "Image read ahead timed out")
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
        let app = AppItem(id: "preview.new", pid: 123001, name: "New", url: URL(fileURLWithPath: "/Preview/New.app"))
        for _ in 0..<10 { preloader.activate(app) }
        try wait { reads.count == 1 }
        settle()
        for _ in 0..<10 { preloader.activate(app) }
        settle()
        try check(reads.count == 1, "Cached app was read again")
        // Manual/automatic insertion and a resource resolved after insertion.
        func icon(_ digit: String) -> MenuResourceIcon {
            .init(kind: .png, digest: String(repeating: digit, count: 64), template: true,
                  sourceAppID: app.id, sourceAppName: app.name, resourceName: "Synthetic")
        }
        var manual = MenuCommand(appID: app.id, appName: app.name, path: ["File", "Manual"])
        manual.resourceIcon = icon("1")
        settings.commands.append(manual)
        try wait { reads.count == 2 }
        var automatic = MenuCommand(appID: app.id, appName: app.name, path: ["File", "Automatic"], isPinned: false)
        automatic.isAutomatic = true
        settings.commands.append(automatic)
        settle()
        try check(reads.count == 2, "No image should be read before resource resolution")
        settings.commands[1].resourceIcon = icon("2")
        try wait { reads.count == 3 }
        settings.recordUse(manual.id)
        settings.commands[0].isPinned.toggle()
        settle()
        try check(reads.count == 3, "Usage/pin changes caused an image read")
        settings.commands[0].resourceIcon = icon("3")
        try wait { reads.count == 4 }
        // Duplicate picture in a new menu must use the same image cache.
        manual.id = UUID(); manual.resourceIcon = icon("3")
        settings.commands.append(manual)
        settle()
        try check(reads.count == 4, "Shared image was loaded twice")
        // Native cache eviction / refresh with unchanged resource metadata.
        reads.evict()
        preloader.prepareMenus(appID: app.id)
        preloader.activate(app)
        try wait { reads.count == 7 }
        settle()
        settings.commands.removeAll()
        settle()
        try check(reads.count == 7, "Deleting menus read images")
        let pin = PinnedItem(kind: .app, path: "/Preview/Registered.app", bundleID: nil, name: "Registered")
        settings.pins = [pin]
        try wait { reads.count == 8 }
        let newest = URL(fileURLWithPath: "/Preview/LaunchedLater.app")
        preloader.prepareApp(newest)
        try wait { reads.count == 9 }
        preloader.stop()
        settings.pins = [PinnedItem(kind: .app, path: "/Preview/Stopped.app", bundleID: nil, name: "Stopped")]
        preloader.prepareApp(URL(fileURLWithPath: "/Preview/Stopped.app"))
        settle()
        try check(reads.count == 9, "Stopped preloader accepted new work")
        // Exercise the real background loaders with isolated file data and an
        // uninstalled synthetic app URL. The saved user image directory is untouched.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tile-icon-read-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalRoot = SavedMenuImages.root
        defer {
            SavedMenuImages.root = originalRoot; SavedMenuImages.invalidate()
            try? FileManager.default.removeItem(at: root)
        }
        SavedMenuImages.root = root; SavedMenuImages.invalidate()
        let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let realIcon = icon("a"), missingIcon = icon("b")
        try picture.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(realIcon.digest + ".png"))
        let isolated = PreviewFixture(theme: .classic, registeredCount: 0)
        isolated.settings.commands = []
        let live = IconReadAhead(settings: isolated.settings)
        defer { live.stop() }
        let appURL = root.appendingPathComponent("Uninstalled.app")
        live.prepareApp(appURL)
        var imageMenu = MenuCommand(appID: app.id, appName: app.name, path: ["File", "Image"])
        imageMenu.resourceIcon = realIcon
        var missingMenu = MenuCommand(appID: app.id, appName: app.name, path: ["File", "Missing"])
        missingMenu.resourceIcon = missingIcon
        isolated.settings.commands = [imageMenu, missingMenu]
        try wait { AppIconCache.shared.isCached(appURL) && SavedMenuImages.isCached(realIcon) && SavedMenuImages.isCached(missingIcon) }
        settle()
        try check(SavedMenuImages.image(realIcon)?.size == NSSize(width: 8, height: 8), "Actual background image changed its size")
        try check(SavedMenuImages.image(missingIcon) == nil && SavedMenuImages.isCached(missingIcon), "Missing image was not cached safely")
        SavedMenuImages.invalidate()
        live.prepareMenus(appID: app.id)
        try wait { SavedMenuImages.isCached(realIcon) && SavedMenuImages.isCached(missingIcon) }
        settle()
        print("Icon read ahead: new apps, registered items, manual/automatic menus, late/changed resources, cache hits/eviction, usage/pin changes and shutdown passed without reading real apps.")
    }
}
#endif
