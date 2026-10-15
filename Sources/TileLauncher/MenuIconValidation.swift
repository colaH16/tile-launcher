import AppKit
import SwiftUI
import DeckCore

/// Explicit diagnostic, no foreground UI, production defaults, AX or app launch.
enum MenuIconValidation {
    @MainActor static func verify(to directory: URL) throws {
        func check(_ passed: @autoclosure () -> Bool, _ message: String) throws {
            if !passed() { throw NSError(domain: "MenuIconValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("cache")
        SavedMenuImages.root = root
        let repository = MenuIconRepository(root: root)
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
            var command = MenuCommand(appID: "com.apple.Music", appName: "Music", path: ["View", title])
            command.resourceIcon = repository.resolve(command)
            try check(command.resourceIcon?.kind == .symbol && command.resourceIcon?.resourceName == symbol, "Music symbol: \(title)")
            try check(command.resourceIcon.flatMap(SavedMenuImages.image) != nil, "Symbol unavailable: \(symbol)")
            commands.append(command)
        }
        let korean = MenuCommand(appID: "com.apple.Music", appName: "음악", path: ["보기", "보관함에서 아티스트 보기"])
        try check(repository.resolve(korean)?.resourceName == "microphone.dynamic.on.stand", "Korean menu localization")
        let unavailable = MenuCommand(appID: "com.apple.Music", appName: "Music", path: ["View", "Show in Apple Music"])
        try check(repository.resolve(unavailable) == nil, "Unavailable private symbol should not be guessed")
        let restarted = MenuIconRepository(root: root)
        // A nil/changed source has no effect without explicit refresh.
        try restarted.prepare(appID: "com.apple.Music", name: "Music", url: nil, refresh: false)
        try check(restarted.resolve(commands[0]) == commands[0].resourceIcon, "Frozen catalog restart")
        let borrowed = MenuCommand(appID: "synthetic.other", appName: "Other", path: ["View", expected[0].0])
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
        let service = MenuIconService(settings: settings, root: root, applicationURL: { _ in music })
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
        print("Verified 6 Music symbols + Korean, unavailable symbol fallback, persistence, cross-app borrowing, refresh, manual/automatic addition, original PDF/512px bitmap.")
    }
}
