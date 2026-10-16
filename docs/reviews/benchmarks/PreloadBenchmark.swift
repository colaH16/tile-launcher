import AppKit
import CryptoKit
import Darwin
import DeckCore

/// Temporary instrumented Release build. Reads saved configuration; no SettingsStore,
/// AX access, app launch, global monitors or visible windows.
enum PreloadBenchmark {
    struct Sample: Codable { let wallMS: Double; let cpuMS: Double; let checksum: Int }
    static func cpu() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
    }
    static func clock() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }
    @inline(never) static func measure(repeats: Int = 1, _ body: () -> Int) -> Sample {
        let c = cpu(), t = clock()
        var checksum = 0
        for _ in 0..<repeats { checksum &+= autoreleasepool(invoking: body) }
        let wall = clock() - t, cpuUsed = cpu() - c
        return .init(wallMS: wall / Double(repeats), cpuMS: cpuUsed / Double(repeats), checksum: checksum)
    }
    @MainActor static func run(to output: URL) throws {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/dev.cola16.TileLauncher.plist")
        let raw = try PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as? [String: Any] ?? [:]
        let commands = try (raw["menuCommands"] as? Data).map { try JSONDecoder().decode([MenuCommand].self, from: $0) } ?? []
        let pins = try (raw["pinnedItems"] as? Data).map { try JSONDecoder().decode([PinnedItem].self, from: $0) } ?? []
        let history = MenuHistoryPreferences.restore(raw["menuHistoryPreferences"] as? Data)
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleURL)
        var seen = Set<String>()
        let urls = (pins.map(\.url) + running).filter { seen.insert($0.path).inserted }
        let appIDs = Array(Set(commands.map(\.appID))).sorted()
        let now = Date()
        var metrics: [String: Sample] = [:]
        // No icon access before this point in this fresh process.
        metrics["appIcons_first_load_batch"] = measure {
            urls.reduce(0) { $0 + Int(AppIconCache.shared.icon($1).size.width) }
        }
        metrics["appIcons_cached_load_batch"] = measure(repeats: 300) {
            urls.reduce(0) { $0 + Int(AppIconCache.shared.icon($1).size.width) }
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        func draw(_ image: NSImage) -> Int {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: CGRect(x: 0, y: 0, width: 128, height: 128))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.bitmapData.map { Int($0.pointee) } ?? 0
        }
        metrics["appIcons_first_bitmap_draw_batch"] = measure { urls.reduce(0) { $0 + draw(AppIconCache.shared.icon($1)) } }
        metrics["appIcons_cached_bitmap_draw_batch"] = measure(repeats: 30) { urls.reduce(0) { $0 + draw(AppIconCache.shared.icon($1)) } }
        metrics["actualMenuGlyphs_first_batch"] = measure { commands.reduce(0) { $0 + ($1.glyph == .text ? 1 : 2) } }
        metrics["actualMenuGlyphs_repeated_batch"] = measure(repeats: 500) { commands.reduce(0) { $0 + ($1.glyph == .text ? 1 : 2) } }
        func ordered(_ all: [MenuCommand], _ id: String) -> Int {
            MenuCommand.ordered(all, appID: id, history: history, at: now).count
                + MenuCommand.frequentIDs(all, appID: id, history: history, at: now).count
        }
        metrics["actualMenus_first_all_apps"] = measure { appIDs.reduce(0) { $0 + ordered(commands, $1) } }
        metrics["actualMenus_all_apps"] = measure(repeats: 2000) { appIDs.reduce(0) { $0 + ordered(commands, $1) } }
        let largest = appIDs.max { a,b in commands.filter { $0.appID == a }.count < commands.filter { $0.appID == b }.count }
        if let largest {
            metrics["actualMenus_largest_app"] = measure(repeats: 10000) { ordered(commands, largest) }
        }
        var stress: [MenuCommand] = []
        for app in 0..<20 { for index in 0..<100 {
            var command = MenuCommand(appID: "synthetic.\(app)", appName: "Synthetic", path: ["File", "Action \(index)"], isPinned: index % 10 == 0)
            command.isAutomatic = !command.isPinned
            for use in 0..<(index % 4) { command.recordUse(at: now.addingTimeInterval(-Double(index * 60 + use))) }
            stress.append(command)
        } }
        metrics["stress_2000_total_100_target"] = measure(repeats: 3000) { ordered(stress, "synthetic.10") }
        // Isolated sample resources; this Mac's saved commands may have no resource images.
        let root = output.deletingLastPathComponent().appendingPathComponent("sample-images")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        SavedMenuImages.root = root; SavedMenuImages.invalidate()
        _ = draw(NSImage(systemSymbolName: "gear", accessibilityDescription: nil)!)
        let png = bitmap.representation(using: .png, properties: [:])!
        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
        var box = CGRect(x: 0, y: 0, width: 128, height: 128)
        let pdf = CGContext(consumer: consumer, mediaBox: &box, nil)!
        pdf.beginPDFPage(nil); pdf.setFillColor(CGColor(gray: 0.5, alpha: 1)); pdf.fillEllipse(in: box); pdf.endPDFPage(); pdf.closePDF()
        var images: [MenuResourceIcon] = []
        for (kind, bytes) in [(MenuResourceIcon.Kind.png, png), (.pdf, pdfData as Data)] {
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            try bytes.write(to: root.appendingPathComponent(digest + "." + kind.rawValue))
            images.append(.init(kind: kind, digest: digest, template: false,
                sourceAppID: "synthetic", sourceAppName: "Synthetic", resourceName: "sample"))
        }
        metrics["sample_PNG_PDF_first_load_pair"] = measure { images.reduce(0) { $0 + (SavedMenuImages.image($1) == nil ? 0 : 1) } }
        metrics["sample_PNG_PDF_cached_load_pair"] = measure(repeats: 1000) { images.reduce(0) { $0 + (SavedMenuImages.image($1) == nil ? 0 : 1) } }
        metrics["sample_PNG_PDF_first_draw_pair"] = measure { images.reduce(0) { $0 + draw(SavedMenuImages.image($1)!) } }
        metrics["sample_PNG_PDF_cached_draw_pair"] = measure(repeats: 100) { images.reduce(0) { $0 + draw(SavedMenuImages.image($1)!) } }
        let counts: [String: Int] = ["iconURLs": urls.count, "savedPins": pins.count, "savedMenus": commands.count,
            "menuApps": appIDs.count, "largestAppMenus": largest.map { id in commands.filter { $0.appID == id }.count } ?? 0,
            "actualResourceIcons": commands.filter { $0.resourceIcon != nil }.count, "logicalCPUs": ProcessInfo.processInfo.processorCount]
        let json: [String: Any] = ["counts": counts, "metrics": try JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics)),
            "os": ProcessInfo.processInfo.operatingSystemVersionString]
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("Benchmark complete; only aggregate counts and timing written.")
    }
}
