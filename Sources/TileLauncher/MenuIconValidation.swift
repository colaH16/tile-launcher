#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import SwiftUI
import DeckCore
import ApplicationServices

/// Explicit diagnostic, no foreground UI, production defaults, AX or app launch.
enum MenuIconValidation {
    @MainActor static func verify(to directory: URL) throws {
        func check(_ passed: @autoclosure () -> Bool, _ message: String) throws {
            if !passed() { throw NSError(domain: "MenuIconValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("cache")
        SavedMenuImages.root = root
        // The user's macOS list (R191); deterministic regardless of this Mac's settings.
        let languages = ["en-GB", "ko-KR", "ja-JP"]
        let repository = MenuIconRepository(root: root, preferredLanguages: languages)
        let music = URL(fileURLWithPath: "/System/Applications/Music.app")
        let start = Date()
        try repository.prepare(appID: "com.apple.Music", name: "Music", url: music, refresh: true)
        print("Music resource scan: \(Date().timeIntervalSince(start) * 1000) ms; no app launch")
        let expected = [("Show Artist in Library", "microphone.dynamic.on.stand"),
                        ("Show Album in Library", "square.stack"), ("Show Movie in Library", "film"),
                        ("Show TV Show in Library", "tv"),
                        ("Show in iTunes Store", "bag"), ("Show in Playlist", "music.note.list")]
        var commands: [MenuCommand] = []
        for (title, symbol) in expected {
            var command = MenuCommand(appID: "com.apple.Music", appName: "Music", path: ["Song", title])
            command.resourceIcon = repository.resolve(command)
            try check(command.resourceIcon?.kind == .symbol && command.resourceIcon?.resourceName == symbol, "Music symbol: \(title)")
            try check(command.resourceIcon?.sourceIdentity == repository.binding(for: command)?.identity
                      && command.resourceIcon?.sourcePath == command.path, "Icon source identity/path detached from menu")
            try check(command.resourceIcon.flatMap(SavedMenuImages.image) != nil, "Symbol unavailable: \(symbol)")
            commands.append(command)
        }
        let korean = MenuCommand(appID: "com.apple.Music", appName: "음악", path: ["노래", "보관함에서 아티스트 보기"])
        try check(repository.resolve(korean)?.resourceName == "microphone.dynamic.on.stand", "Korean menu localization")
        // Only preferred + US English + development languages are stored, one file per app.
        let stored = Set(repository.localizations(appID: "com.apple.Music") ?? [])
        try check(stored.contains("ko") && stored.contains("ja") && stored.contains("en") && !stored.contains("de"),
                  "Stored languages: \(stored.sorted())")
        let appFiles = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("apps-v3").path)) ?? []
        try check(appFiles.count == 1, "One catalog file per app")
        // A Korean name maps back to the English menu and vice versa.
        let english = MenuCommand(appID: "com.apple.Music", appName: "Music", path: ["Song", "Show Artist in Library"])
        let binding = repository.binding(for: english)
        try check(binding?.paths.contains(["노래", "보관함에서 아티스트 보기"]) == true, "Item-scoped Korean path")
        var aliased = english; aliased.resourceBinding = binding
        try check(MenuPathMatch.matches(["노래", "보관함에서 아티스트 보기"], aliased), "Korean path matches same resource item")
        try check(!MenuPathMatch.matches(["보기", "보관함에서 아티스트 보기"], aliased), "Wrong parent must not match")
        let wrongParent = MenuCommand(appID: "com.apple.Music", appName: "Music", path: ["View", english.title])
        try check(repository.resolve(wrongParent) == nil, "Icon matched a leaf under the wrong parent")
        try check(!(binding?.paths.joined().contains("Künstler in der Mediathek anzeigen") ?? false), "Unselected language stored")
        // Compiled nib folders: newest runtime archive, named after the folder.
        let folder = URL(fileURLWithPath: "/X/Base.lproj/MainMenu.nib")
        let grouped = MenuIconRepository.nibs([folder.appendingPathComponent("keyedobjects-101300.nib"),
                                                folder.appendingPathComponent("keyedobjects-110000.nib"),
                                                folder.appendingPathComponent("designable.nib"),
                                                URL(fileURLWithPath: "/X/Base.lproj/Other.nib")])
        try check(grouped.map(\.name).sorted() == ["MainMenu", "Other"]
                  && grouped.first { $0.name == "MainMenu" }?.url.lastPathComponent == "keyedobjects-110000.nib", "Nib folder grouping")
        let unavailable = MenuCommand(appID: "com.apple.Music", appName: "Music", path: ["Song", "Show in Apple Music"])
        try check(repository.resolve(unavailable) == nil, "Unavailable private symbol should not be guessed")
        let restarted = MenuIconRepository(root: root, preferredLanguages: languages)
        // A nil/changed source has no effect without explicit refresh.
        try restarted.prepare(appID: "com.apple.Music", name: "Music", url: nil, refresh: false)
        try check(restarted.resolve(commands[0]) == commands[0].resourceIcon, "Frozen catalog restart")
        let borrowed = MenuCommand(appID: "synthetic.other", appName: "Other", path: ["Song", expected[0].0])
        try check(restarted.resolve(borrowed)?.sourceAppID == "com.apple.Music", "Cross-app donor provenance")
        do {
            try restarted.prepare(appID: "com.apple.Music", name: "Music", url: nil, refresh: true)
            try check(false, "Missing source should fail refresh")
        } catch is CocoaError { }
        try check(restarted.resolve(commands[0]) == commands[0].resourceIcon, "Failed refresh erased old icon")

        // Preserve a true PDF vector and a 512px bitmap, without downsizing.
        let pdf = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 24, height: 24)
        let context = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &media, nil)!
        context.beginPDFPage(nil); context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 4, y: 4, width: 16, height: 16)); context.endPDFPage(); context.closePDF()
        let vector = NSImage(data: pdf as Data)!
        let original = MenuIconRepository.original(vector)
        try check(original?.0 == .pdf && original?.1 == pdf as Data, "PDF rasterized or changed")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: CGSize(width: 32, height: 32)); image.addRepresentation(bitmap)
        let preserved = MenuIconRepository.original(image)
        try check(preserved?.0 == .png && preserved.flatMap { NSBitmapImageRep(data: $0.1) }?.pixelsWide == 512, "Bitmap downsized")

        let suite = "MenuIconValidation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.commands = []
        settings.menuCapture.enabled = true
        let service = MenuIconService(settings: settings, root: root, preferredLanguages: languages, applicationURL: { _ in music })
        var manual = commands[0]; manual.resourceIcon = nil
        settings.addCommand(manual)
        let captured = CapturedMenu(appID: "com.apple.Music", appName: "Music", path: commands[1].path)
        settings.recordCapturedMenu(captured)
        settings.recordCapturedMenu(captured)
        let deadline = Date().addingTimeInterval(10)
        while settings.commands.contains(where: { $0.resourceIcon == nil }) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try check(settings.commands.count == 2 && settings.commands.allSatisfy { $0.resourceIcon != nil }, "Automatic/manual addition")
        settings.setSymbol("star", for: settings.commands[0].id)
        settings.onRefreshMenuIcons?("com.apple.Music")
        while settings.refreshingMenuIcons.contains("com.apple.Music") && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try check(!settings.refreshingMenuIcons.contains("com.apple.Music") && settings.commands[0].glyph == .symbol("star"), "Refresh overwrote manual choice")
        let saved = settings.commands[0]
        var rebound = saved
        rebound.axIdentifier = "validation.alternate"
        settings.addCommand(rebound)
        // A late legacy lookup must not overwrite a newer explicit selection.
        settings.updateMenuIdentifier("validation.earlier", for: saved.id)
        try check(settings.commands.count == 2 && settings.commands[0].id == saved.id
                  && settings.commands[0].axIdentifier == rebound.axIdentifier
                  && settings.commands[0].symbol == saved.symbol && settings.commands[0].isPinned == saved.isPinned
                  && settings.commands[0].observedCount == saved.observedCount,
                  "Rebinding replaced tile identity, icon, pin or history")
        let savedID = saved.id
        try check(saved.resourceBinding != nil && saved.id == manual.id && saved.isPinned, "Binding changed saved identity/pin")
        settings.removeCommand(saved)
        let beforeCapture = settings.commands.count
        settings.recordCapturedMenu(CapturedMenu(appID: "com.apple.Music", appName: "Music", path: korean.path))
        try check(settings.commands.count == beforeCapture, "Excluded Korean translation was collected")
        var readded = saved; readded.resourceBinding = nil; readded.resourceIdentityVersion = nil
        settings.addCommand(readded)
        let restoredDeadline = Date().addingTimeInterval(10)
        while settings.commands.first(where: { $0.id == savedID })?.resourceIdentityVersion != 1 && Date() < restoredDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try check(!settings.menuCapture.excludedMenus.contains(MenuIdentity(appID: "com.apple.Music", path: korean.path)), "Manual re-add did not restore translated paths")
        let pending = MenuCommand(appID: "com.apple.Music", appName: "Music", path: commands[2].path)
        settings.addCommand(pending); settings.removeCommand(pending)
        settings.onRefreshMenuIcons?("com.apple.Music")
        while settings.refreshingMenuIcons.contains("com.apple.Music") && Date() < restoredDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try check(!settings.commands.contains(where: { $0.id == pending.id }), "Deleted pending menu resurrected")
        try check(settings.menuCapture.excludedMenus.contains(MenuIdentity(appID: "com.apple.Music", path: ["노래", "보관함에서 영화 보기"])), "Pending deletion lost translated exclusion")
        // Production reader with mocked IPC boundaries; never queries/presses a real window.
        let element = AXUIElementCreateApplication(getpid())
        var reads = 0
        let timedOut = WindowAttributeReader.read(element, batch: { _, _ in (.notImplemented, nil) }, single: { _, key in
            reads += 1
            return key == kAXRoleAttribute ? (.success, kAXWindowRole as CFString) : (.cannotComplete, nil)
        })
        try check(timedOut == nil && reads == 2, "Attribute fallback continued after timeout")
        var error = AXError.cannotComplete
        let errorValue = AXValueCreate(.axError, &error)!
        var values = Array<AnyObject>(repeating: NSNull(), count: 6); values[2] = errorValue
        let batchTimeout = WindowAttributeReader.read(element, batch: { _, _ in (.success, values) }, single: { _, _ in
            reads += 1; return (.success, nil)
        })
        try check(batchTimeout == nil && reads == 2, "Embedded batch timeout was ignored")
        withExtendedLifetime(service) { }
        let gallery = VStack(alignment: .leading, spacing: 14) {
            Text("Music 메뉴 리소스 · SF Symbols").font(.headline)
            ForEach(commands) { command in
                HStack(spacing: 20) {
                    Image(systemName: command.resourceIcon!.resourceName).font(.system(size: 36, weight: .light)).frame(width: 52)
                    VStack(alignment: .leading) {
                        Text(command.title)
                        Text(command.resourceIcon!.resourceName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(24).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
        try PreviewExport.save(gallery, to: directory.appendingPathComponent("music-resource-symbols.png"))
        settings.commands = commands
        let musicApp = AppItem(id: "com.apple.Music", pid: 0, name: "Music", url: music)
        let settingsPane = MenuSettingsView(settings: settings, preferredApp: musicApp, additionRequest: nil,
            additionSize: CGSize(width: 516, height: 700), applicationProvider: { [musicApp] })
            .frame(width: 548, height: 900).background(Color(nsColor: .windowBackgroundColor))
        try PreviewExport.save(settingsPane, to: directory.appendingPathComponent("music-menu-settings.png"))
        print("Verified item-scoped paths/6 Music symbols, stored languages \(stored.sorted()), ID/pin preservation, translated exclusion/re-add/deletion race, bounded AX fallback, original PDF/512px bitmap.")
    }
}
#endif
