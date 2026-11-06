#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import SwiftUI
import DeckCore

/// Synthetic, offscreen rendering of the production caption and menu tile.
/// Uses an isolated preview settings suite and a temporary resource-image root;
/// never acquires the app instance, installs monitors, queries AX or runs actions.
enum MenuTileCaptionValidation {
    private struct InkBounds {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
    }

    @MainActor static func verify(to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "TileLauncher.MenuTileCaptionValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func bitmap(_ url: URL) throws -> NSBitmapImageRep {
            guard let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
                throw NSError(domain: "TileLauncher.MenuTileCaptionValidation", code: 2)
            }
            return image
        }
        func bounds(_ image: NSBitmapImageRep, dark: Bool, threshold: CGFloat) -> InkBounds? {
            var result: InkBounds?
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let components = [color.redComponent, color.greenComponent, color.blueComponent]
                    let contrast = dark ? components.max()! : 1 - components.min()!
                    guard color.alphaComponent > 0.9, contrast > threshold else { continue }
                    if let previous = result {
                        result = InkBounds(minX: min(previous.minX, x), minY: min(previous.minY, y),
                                           maxX: max(previous.maxX, x), maxY: max(previous.maxY, y))
                    } else { result = InkBounds(minX: x, minY: y, maxX: x, maxY: y) }
                }
            }
            return result
        }
        func caption(title: String, parent: String?, scale: CGFloat, width: CGFloat, dark: Bool) -> some View {
            MenuTileCaption(title: title, parentPath: parent, scale: scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MenuTileCaption.Metrics.inset * scale)
                .frame(width: width, height: 54 * scale, alignment: .bottomLeading)
                .foregroundStyle(dark ? Color.white : Color.black)
                .background(dark ? Color.black : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        try check(MenuTileCaption.Metrics.pathSize / MenuTileCaption.Metrics.nameSize == 0.75,
                  "Parent text must remain 75% of the unchanged name size")
        for scale: CGFloat in [1, 1.4] {
            for dark in [false, true] {
                let suffix = "\(scale)-\(dark ? "dark" : "light")"
                let width: CGFloat = 176 * scale
                let baseURL = directory.appendingPathComponent("caption-no-parent-\(suffix).png")
                let parentURL = directory.appendingPathComponent("caption-long-parent-\(suffix).png")
                let title = "Export TSV"
                try PreviewExport.save(caption(title: title, parent: nil, scale: scale, width: width, dark: dark),
                                       dark: dark, to: baseURL)
                let saved = ["File", "A very long parent menu", "Export To", title]
                try PreviewExport.save(caption(title: title, parent: MenuTileCaption.parentPath(of: saved),
                                               scale: scale, width: width, dark: dark), dark: dark, to: parentURL)
                let base = try bitmap(baseURL), parent = try bitmap(parentURL)
                guard let baseName = bounds(base, dark: dark, threshold: 0.82),
                      let baseInk = bounds(base, dark: dark, threshold: 0.04),
                      let parentName = bounds(parent, dark: dark, threshold: 0.82),
                      let allParent = bounds(parent, dark: dark, threshold: 0.04) else {
                    throw NSError(domain: "TileLauncher.MenuTileCaptionValidation", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Production caption rendered no visible name/path ink"])
                }
                try check(base.pixelsWide == parent.pixelsWide && base.pixelsHigh == parent.pixelsHigh,
                          "Adding a parent must not resize the fixed tile footer surface")
                try check(abs(baseName.minY - parentName.minY) <= 1 && abs(baseName.maxY - parentName.maxY) <= 1
                          && abs(baseName.minX - parentName.minX) <= 1 && abs(baseName.maxX - parentName.maxX) <= 1,
                          "The production name raster must stay at its bottom position and retain the same text")
                try check(allParent.minY < parentName.minY - 1,
                          "The smaller path must produce a distinct row above the fixed name")
                try check(MenuTileCaption.glyphReserve(hasParentPath: true, scale: scale)
                          > MenuTileCaption.glyphReserve(hasParentPath: false, scale: scale),
                          "The glyph must reserve space for the actual additional text row")
                for (index, invalid) in [[title], ["", title], ["File", "  ", title]].enumerated() {
                    let invalidParent = MenuTileCaption.parentPath(of: invalid)
                    try check(invalidParent == nil, "Missing or partly unknown parents must not invent a path line")
                    let url = directory.appendingPathComponent("caption-unknown-parent-\(index)-\(suffix).png")
                    try PreviewExport.save(caption(title: title, parent: invalidParent, scale: scale, width: width, dark: dark),
                                           dark: dark, to: url)
                    let image = try bitmap(url)
                    guard let ink = bounds(image, dark: dark, threshold: 0.04) else {
                        throw NSError(domain: "TileLauncher.MenuTileCaptionValidation", code: 4)
                    }
                    try check(abs(ink.minY - baseInk.minY) <= 1 && abs(ink.maxY - baseInk.maxY) <= 1,
                              "Unknown parent must not leave an empty extra row or move the name")
                }
            }
        }

        let resources = directory.appendingPathComponent("synthetic-resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let oldRoot = SavedMenuImages.root
        SavedMenuImages.root = resources; SavedMenuImages.invalidate()
        defer { SavedMenuImages.root = oldRoot; SavedMenuImages.invalidate() }
        let digest = String(repeating: "a", count: 64)
        let image = NSImage(size: CGSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
            NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 10, y: 7, width: 12, height: 18)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let picture = NSBitmapImageRep(data: tiff),
              let png = picture.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TileLauncher.MenuTileCaptionValidation", code: 5)
        }
        try png.write(to: resources.appendingPathComponent(digest + ".png"))
        func command(_ path: [String], symbol: String? = nil, pinned: Bool = false) -> MenuCommand {
            var value = MenuCommand(appID: "caption.fixture", appName: "Fixture", path: path, isPinned: pinned)
            value.symbol = symbol; value.useCount = 12; value.observedCount = 3
            return value
        }
        var resource = command(["File", "Export To", "Resource Icon"])
        resource.resourceIcon = MenuResourceIcon(kind: .png, digest: digest, template: false,
            sourceAppID: "caption.fixture", sourceAppName: "Fixture", resourceName: "fixture.png")
        let symbol = command(["File", "A very long parent menu for truncation", "Export To", "Long Symbol Name"],
                             symbol: "square.and.arrow.up", pinned: true)
        var shortcut = command(["Tools", "Transform", "Shortcut"], symbol: MenuSymbolName.hidden)
        shortcut.shortcut = .init(key: "k", modifiers: 0)
        let text = command(["File", "Text Parent", "Only Once"], symbol: MenuSymbolName.hidden)
        let missing = command(["No Parent"], symbol: "doc")
        var option = command(["File", "Export To", "TSV…"], symbol: "tablecells", pinned: true)
        option.optionAction = .init(path: ["File", "Export To", "All TSV…"], identifier: "fixture.option")
        let samples = [resource, symbol, shortcut, text, missing, option]
        try check(resource.glyph == .resource(resource.resourceIcon!) && symbol.glyph == .symbol("square.and.arrow.up")
                  && shortcut.glyph == .shortcut(shortcut.shortcut!.display) && text.glyph == .text,
                  "The contact sheet must exercise actual resource, symbol, shortcut and text glyph branches")
        let fixture = PreviewFixture(theme: .classic, registeredCount: 0, recentCount: 0)
        let originalCommands = fixture.settings.commands
        let before = samples
        var actions = 0
        let launches = ApplicationLaunchMonitor(running: { [] }, observesSystem: false, open: { _, _ in })
        func deck(labels: Bool = true, appearance: MenuAppearance = .selected) -> DeckView {
            DeckView(content: fixture.content, settings: fixture.settings, browser: fixture.browser,
                presentation: fixture.presentation, launches: launches, selectApp: { _ in }, selectPin: { _ in },
                selectMenu: { _, _, _ in actions += 1 }, selectOptionMenu: { _, _, _ in actions += 1 },
                changeProfile: { _ in }, cycleProfile: { _ in }, selectWindow: { _ in }, openURL: { _ in },
                openInFinder: { _ in }, openTrash: {}, showSettings: { _ in }, requestPermission: {}, pinOverlay: {},
                menuAppearance: appearance, startTileLabels: labels, dismiss: {})
        }
        for (label, scale, unit) in [("regular", CGFloat(1), CGFloat(104)),
                                      ("scaled", CGFloat(1.4), CGFloat(145.6)),
                                      ("tight", CGFloat(1), CGFloat(86))] {
            fixture.content.snapshot.layout = PanelLayout.calculate(
                visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440), cursor: .zero, scale: scale)
            for dark in [false, true] {
                let view = deck()
                let sheet = VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(samples) { sample in
                            VStack(spacing: 4) {
                                Text(sample.glyph == .text ? "Text: one name + parent" : sample.title).font(.system(size: 10))
                                view.menuTileForValidation(sample)
                                    .frame(width: sample.isPinned ? unit * 2 + 6 * scale : unit, height: unit)
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack { Text("Small recentPastel").font(.system(size: 10))
                            deck(appearance: .recentPastel).menuTileForValidation(symbol, small: true)
                                .frame(width: unit, height: unit / 2) }
                        VStack { Text("Legacy labels").font(.system(size: 10))
                            deck(labels: false).menuTileForValidation(symbol).frame(width: unit * 2 + 6 * scale, height: unit) }
                        VStack { Text("Large count + Option").font(.system(size: 10))
                            let largeCount: MenuCommand = { var copy = option; copy.useCount = 123_456; return copy }()
                            view.menuTileForValidation(largeCount).frame(width: unit * 2 + 6 * scale, height: unit) }
                    }
                }
                .padding(16).background(dark ? Color.black : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
                let url = directory.appendingPathComponent("menu-tile-caption-\(label)-\(dark ? "dark" : "light").png")
                try PreviewExport.save(sheet, dark: dark, to: url)
                let rendered = try bitmap(url)
                try check(rendered.pixelsWide > 500 && rendered.pixelsHigh > Int(unit * 2),
                          "The actual full-tile contact sheet must include both regular and regression control rows")
            }
        }
        try check(actions == 0 && samples == before && fixture.settings.commands == originalCommands,
                  "Rendering captions must not execute actions, mutate command identities/paths, or edit saved settings")
        print("Menu tile caption: actual renderer keeps name baseline, path above at 75%, unknown-parent collapse; full glyph/Option/badge/control sheets at 1×/1.4×/tight light/dark exported without AX or live app actions.")
    }
}
#endif
