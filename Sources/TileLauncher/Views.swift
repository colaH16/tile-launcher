import AppKit
import SwiftUI
import DeckCore

private struct HeaderControlsKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

struct Icon: View {
    let url: URL?
    var size: CGFloat = 34
    @Environment(\.deckScale) private var scale
    var body: some View {
        Group {
            if let image = PreviewIconAssets.image(for: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else if url?.scheme == "tile-preview", let symbol = url?.host {
                // Synthetic icons keep offscreen comparisons independent of
                // WindowServer's native app-icon representation caching.
                let color: Color = symbol == "terminal" ? .green : symbol == "calendar" ? .red : symbol == "note.text" ? .orange : .blue
                ZStack {
                    RoundedRectangle(cornerRadius: size * scale / 5).fill(color)
                    Image(systemName: symbol).font(.system(size: size * scale * 0.58, weight: .semibold)).foregroundStyle(.white)
                }
            } else {
                Image(nsImage: AppIconCache.shared.icon(url)).resizable().interpolation(.high)
            }
        }
            .frame(width: size * scale, height: size * scale)
            .accessibilityHidden(true)
    }
}
private struct RegisteredTileStyle: ButtonStyle {
    let selected: Bool
    let emphasized: Bool
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected, emphasized: emphasized)
    }
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let emphasized: Bool
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.deckTheme) private var theme
        @Environment(\.tileColors) private var colors
        @Environment(\.deckScale) private var scale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: theme.isClassic ? 0 : 12 * scale, style: .continuous) }
        var body: some View {
            let palette = DeckPalette(section: .registered, emphasized: emphasized,
                                      dark: scheme == .dark, theme: theme, colors: colors)
            configuration.label
                .foregroundStyle(palette.ink, palette.secondary)
                .contentShape(shape)
                .background(palette.fill.opacity(theme.isClassic || reduceTransparency ? 1 : 0.96), in: shape)
                .overlay {
                    shape.fill(palette.ink.opacity(selected || configuration.isPressed ? 0.22 : hovering ? 0.07 : 0))
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(selected ? palette.ink
                                       : Color.primary.opacity(contrast == .increased ? 0.5 : hovering ? 0.22 : 0.12),
                                       lineWidth: selected ? 3 : 1)
                        .allowsHitTesting(false)
                }
                .onHover { hovering = $0 }
                .offset(y: selected && !reduceMotion ? 2 * scale : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        }
    }
}
private struct TileStyle: ButtonStyle {
    var section: TileSection = .menus
    var emphasized = false
    var selected = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, section: section, emphasized: emphasized, selected: selected, compact: compact)
    }
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let section: TileSection
        let emphasized: Bool
        let selected: Bool
        let compact: Bool
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.deckTheme) private var theme
        @Environment(\.tileColors) private var colors
        @Environment(\.deckScale) private var scale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            let palette = DeckPalette(section: section, emphasized: emphasized, dark: scheme == .dark, theme: theme, colors: colors)
            let shape = RoundedRectangle(cornerRadius: theme.isClassic ? 0 : (compact ? 8 : 14) * scale, style: .continuous)
            configuration.label
                .foregroundStyle(palette.ink, palette.secondary)
                .contentShape(shape)
                .background {
                    ZStack {
                        shape.fill(palette.fill.opacity(theme.isClassic || reduceTransparency ? 1 : 0.96))
                        shape.fill(palette.ink.opacity(selected || configuration.isPressed ? 0.22 : hovering ? 0.10 : 0))
                    }.allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(selected || configuration.isPressed ? palette.ink
                                       : palette.ink.opacity(hovering ? 0.65 : contrast == .increased ? 0.55 : 0.08),
                                       lineWidth: selected ? 3 : configuration.isPressed || hovering ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .onHover { hovering = $0 }
                .offset(y: selected && !reduceMotion ? 2 * scale : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        }
    }
}
struct DeckView: View {
    @ObservedObject var content: OverlayContent
    private var snapshot: OverlaySnapshot { content.snapshot }
    @ObservedObject var settings: SettingsStore
    @ObservedObject var browser: FolderBrowser
    @ObservedObject var presentation: OverlayPresentation
    @ObservedObject var launches = ApplicationLaunchMonitor()
    let selectApp: (AppItem) -> Void
    let selectPin: (PinnedItem) -> Void
    let selectMenu: (MenuCommand, AppItem?, WindowItem?) -> Void
    let changeProfile: (String?) -> Void
    let cycleProfile: (Int) -> Void
    @State private var editedMenus: [MenuCommand]?
    let selectWindow: (WindowItem) -> Void
    let openURL: (URL) -> Void
    let openInFinder: (URL) -> Void
    let openTrash: () -> Void
    let showSettings: (SettingsDestination) -> Void
    let requestPermission: () -> Void
    let pinOverlay: () -> Void
    var resizeForContent: (Int, CGFloat) -> Void = { _, _ in }
    var quitApplication: (WindowItem) -> Void = { _ in }
    var recentAppearance: RecentAppearance = .locationColor
    var menuAppearance: MenuAppearance = .selected
    var startTileLabels = true
    /// R183 comparison: the 0.28 window-color layer above the native glass.
    var backdropTint = true
    // Synthetic comparison inputs only; production callers keep all defaults.
    var previewWindowSizes: [RecentTileSize]? = nil
    var previewEmphasizedWindows: Set<UUID>? = nil
    var previewRecentLegend: String? = nil
    var previewDesktopColumns: DesktopColumnsPreviewData? = nil
    var previewLargeWindowIcons = false
    var previewBalancedWindowLabels = false
    let dismiss: () -> Void
    private var compact: Bool { snapshot.layout.compact }
    private var registeredItems: [PinnedItem] { presentation.profile?.items ?? snapshot.pins }
    private var profileName: String { presentation.profile?.name ?? snapshot.profileName }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var deckScheme
    private func u(_ value: CGFloat) -> CGFloat { value * snapshot.layout.scale }
    private func font(_ style: NSFont.TextStyle) -> Font {
        .system(size: u(NSFont.preferredFont(forTextStyle: style).pointSize))
    }
    private var firstWindowIDs: Set<UUID> {
        let first = RecentWindowPolicy.firstAppearances(apps: snapshot.windows.map(\.appKey),
                                                       applications: snapshot.windows.map(\.isApplication))
        return Set(snapshot.windows.indices.filter { first[$0] }.map { snapshot.windows[$0].id })
    }

    var body: some View {
        deckContents
            .frame(width: snapshot.layout.frame.width, height: snapshot.layout.frame.height, alignment: .topLeading)
            .environment(\.deckScale, snapshot.layout.scale)
            .font(.system(size: NSFont.systemFontSize))
            // Layout and text are drawn at their final point sizes. The native
            // drag view and SwiftUI button anchors share physical coordinates.
            .overlayPreferenceValue(HeaderControlsKey.self) { controls in
                GeometryReader { geometry in
                    OverlayDragHandle(enabled: presentation.isPinned,
                                      excludedRects: controls.map { geometry[$0] })
                        .frame(height: DeckSpacing.header(compact: compact, scale: snapshot.layout.scale))
                        .allowsHitTesting(presentation.isPinned)
                }
            }
    }

    private var deckContents: some View {
        VStack(spacing: u(0)) {
            header
            VStack(alignment: .leading, spacing: DeckSpacing.footerTop) {
                if browser.current != nil {
                    folderContents
                } else {
                    GeometryReader { area in
                        let content = DeckContentLayout(width: snapshot.layout.contentSize.width,
                                                        availableHeight: area.size.height,
                                                        registeredCount: registeredItems.count, compact: compact,
                                                        scale: snapshot.layout.scale, workRows: workRows)
                        VStack(spacing: u(0)) {
                            workArea(height: content.workHeight)
                            Color.clear.frame(height: content.gap)
                            registeredSection.frame(height: content.registeredHeight)
                            Spacer(minLength: u(0))
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: presentation.execution != nil || launches.statusText != nil ? "arrow.up.right" : presentation.isPinned ? "pin.fill" : "option")
                    Text(presentation.selectionTitle.map { "\($0) · Option을 놓으면 실행" }
                         ?? launches.statusText
                         ?? presentation.execution.map { "실행 요청: \($0.title)" }
                         ?? (compact ? "⌥X 고정 · ⌥W 닫기 · ⌥, 설정"
                         : presentation.isPinned ? "상단 드래그로 이동 · ⌥W 닫기 · ⌥, 설정" : "놓으면 닫기 · ⌥X 고정 · ⌥, 설정"))
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Text(compact ? "⌥A/S ← · ⌥D/F →" : "⌥A/S 이전 · ⌥D/F 다음")
                        .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
                .frame(height: DeckSpacing.footerLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DeckSpacing.edge)
            .padding(.bottom, DeckSpacing.footerBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.deckTheme, settings.theme)
        .environment(\.tileColors, settings.tileColors)
        .background {
            // The AppKit surface clips this fill and the native glass together.
            Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : backdropTint ? 0.28 : 0)
        }
        .onChange(of: snapshot.commands) { _, _ in editedMenus = nil }
        .onChange(of: registeredItems.count) { _, count in resizeForContent(count, workRows) }
        .onChange(of: workRows) { _, rows in resizeForContent(registeredItems.count, rows) }
        .onChange(of: browser.current) { _, current in
            if current == nil { resizeForContent(registeredItems.count, workRows) }
        }
    }

    private var header: some View {
        ZStack {
            OverlayTitleView(
                iconURL: browser.current ?? snapshot.context?.url
                    ?? snapshot.windows.first { $0.appName == snapshot.context?.name }?.appURL,
                appName: headerTitle, windowName: headerSubtitle)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 88)
            .allowsHitTesting(false)

            HStack(spacing: 8) {
                Button {
                    if presentation.isPinned { dismiss() } else { pinOverlay() }
                } label: {
                    Image(systemName: presentation.isPinned ? "xmark" : "pin")
                        .font(.system(size: 13)).frame(width: 24, height: 24)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.regular)
                .help(presentation.isPinned ? "닫기 · Esc · ⌘W · ⌥W" : "창 고정 · ⌥X · Option을 놓아도 유지")
                .accessibilityLabel(presentation.isPinned ? "고정된 오버레이 닫기" : "오버레이 고정")
                .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }

                if browser.current != nil {
                    Button(action: browser.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.regular)
                    .help("뒤로")
                    .accessibilityLabel("이전 폴더로 이동")
                    .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }
                }
                Spacer()
                Button { showSettings(.general) } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13)).frame(width: 24, height: 24)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.regular).help("설정 · ⌘, 또는 ⌥,")
                .accessibilityLabel("설정")
                .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }
            }
        }
        .frame(height: DeckSpacing.headerContent(compact: compact, scale: snapshot.layout.scale))
        .padding(.horizontal, DeckSpacing.toolbarHorizontal)
        .padding(.top, DeckSpacing.toolbarTop)
        .padding(.bottom, DeckSpacing.toolbarBottom)
    }

    private var headerTitle: String {
        guard let current = browser.current else { return snapshot.context?.name ?? AppIdentity.name }
        return browser.path.count == 1 ? browser.rootName : current.lastPathComponent
    }
    private var headerSubtitle: String {
        if browser.current != nil { return browser.path.count == 1 ? "등록한 폴더" : browser.rootName }
        return snapshot.contextWindowTitle ?? "지금 하던 일에서, 다음으로"
    }

    private var geometry: DeckGeometry { DeckGeometry(width: snapshot.layout.contentSize.width, compact: compact, scale: snapshot.layout.scale) }
    private var menuItems: [MenuCommand] { editedMenus ?? snapshot.commands }
    private var workRows: CGFloat {
        recentAppearance == .locationColor && previewDesktopColumns == nil && previewWindowSizes == nil
            ? snapshot.workRows(commands: menuItems) : 3.3
    }
    private func workArea(height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: DeckSpacing.columns) {
            if !compact { menuSection(height: height).frame(width: geometry.menuWidth) }
            recentSection(height: height).frame(width: geometry.windowWidth)
        }
    }
    private func rows(_ spans: [Int], columns: Int) -> [[TilePlacement]] {
        let placements = TileArrangement.place(spans: spans, columns: columns)
        return (0..<(placements.last.map { $0.row + 1 } ?? 0)).map { row in placements.filter { $0.row == row } }
    }
    private func tileWidth(_ span: Int) -> CGFloat { geometry.unit * CGFloat(span) + geometry.gap * CGFloat(span - 1) }

    private func menuSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DeckSpacing.sectionTitle) {
            HStack(spacing: 8) {
                sectionTitle("메뉴", symbol: "command")
                Spacer()
                Button { showSettings(.addMenu) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("설정에서 앱별 메뉴 추가")
            }.frame(height: 20)
            if menuItems.isEmpty {
                Button { showSettings(.addMenu) } label: {
                    VStack(alignment: .leading, spacing: u(9)) {
                        Image(systemName: "command").font(font(.title2))
                        Text("앱별 메뉴 추가").font(font(.callout).weight(.medium))
                        Text("설정 → 메뉴에서 자주 쓰는 동작을 등록하세요.")
                            .font(font(.caption1)).foregroundStyle(.secondary)
                    }.padding(u(14)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }.buttonStyle(TileStyle())
            } else if menuAppearance == .recentPastel {
                let sizes = menuItems.map { command in
                    command.isPinned ? RecentTileSize.wide : snapshot.frequentMenuIDs.contains(command.id) ? .square : .application
                }
                let packed = RecentTileArrangement.place(sizes: sizes, columns: 8)
                let micro = (geometry.unit - geometry.gap) / 2
                let bottom = packed.map { $0.row + $0.height }.max() ?? 0
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        ForEach(packed, id: \.index) { place in
                            menuTile(menuItems[place.index], small: place.height == 1)
                                .frame(width: micro * CGFloat(place.width) + geometry.gap * CGFloat(place.width - 1),
                                       height: micro * CGFloat(place.height) + geometry.gap * CGFloat(place.height - 1))
                                .offset(x: CGFloat(place.column) * (micro + geometry.gap),
                                        y: CGFloat(place.row) * (micro + geometry.gap))
                        }
                    }.frame(width: geometry.menuWidth,
                            height: CGFloat(bottom) * micro + CGFloat(max(0, bottom - 1)) * geometry.gap,
                            alignment: .topLeading)
                }.scrollIndicators(.visible)
            } else {
                let packed = rows(menuItems.map {
                    ($0.isPinned || (menuAppearance == .original && snapshot.frequentMenuIDs.contains($0.id))) ? 2 : 1
                }, columns: 4)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: geometry.gap) {
                        ForEach(packed.indices, id: \.self) { row in
                            HStack(spacing: geometry.gap) {
                                ForEach(packed[row], id: \.index) { place in
                                    menuTile(menuItems[place.index]).frame(width: tileWidth(place.span), height: geometry.unit)
                                }
                                Spacer(minLength: u(0))
                            }
                        }
                    }
                }.scrollIndicators(.visible)
            }
        }.frame(height: height)
    }
    private func menuTile(_ command: MenuCommand, small: Bool = false) -> some View {
        var colors = settings.tileColors
        if menuAppearance == .recentGraySquare && !command.isPinned && !snapshot.frequentMenuIDs.contains(command.id) {
            colors.menus = TileColor(0x777777)
        }
        return Button { selectMenu(command, snapshot.context, snapshot.windows.first { $0.pid == snapshot.context?.pid }) } label: {
            if startTileLabels {
                let glyph = command.glyph
                ZStack(alignment: .bottomLeading) {
                    switch glyph {
                    case .resource(let icon):
                        if icon.kind == .symbol {
                            Image(systemName: icon.resourceName).font(.system(size: u(small ? 26 : 44), weight: .light))
                                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, u(small ? 12 : 22))
                        } else if let image = SavedMenuImages.image(icon) {
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(width: u(small ? 26 : 44), height: u(small ? 26 : 44))
                                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, u(small ? 12 : 22))
                        }
                    case .symbol(let symbol):
                        Image(systemName: symbol).font(.system(size: u(small ? 26 : 44), weight: .light))
                            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, u(small ? 12 : 22))
                    case .shortcut(let keys):
                        Text(keys).font(.system(size: u(small ? 18 : 34), weight: .medium, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, u(small ? 4 : 12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, u(small ? 12 : 22))
                    case .text:
                        // Windows 8 text-only tile: the name itself is the large
                        // content, with its parent menu as the small bottom label.
                        Text(command.title).font(.system(size: u(small ? 11 : 19), weight: .semibold))
                            .lineLimit(3).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, u(small ? 3 : 8)).padding(.top, u(small ? 3 : 8))
                            .padding(.trailing, u(small ? 10 : 28)).padding(.bottom, u(small ? 12 : 22))
                    }
                    Text(glyph == .text ? command.path.dropLast().joined(separator: " › ") : command.title)
                        .font(.system(size: u(small ? 8 : 12), weight: .medium)).lineLimit(1)
                        .foregroundStyle(glyph == .text ? HierarchicalShapeStyle.secondary : .primary)
                        .padding(u(small ? 3 : 8))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        VStack(spacing: u(3)) {
                            if command.isPinned { Image(systemName: "pin.fill") }
                            Text("\(command.totalUseCount)회")
                        }.font(.system(size: u(9))).padding(u(8))
                    }
            } else {
            VStack(alignment: .leading, spacing: u(2)) {
                HStack(alignment: .top) {
                    Image(systemName: "command").font(.system(size: u(small ? 12 : 20)))
                    Spacer(minLength: u(small ? 0 : 4))
                    VStack(alignment: .trailing, spacing: u(1)) {
                        if !small {
                            Image(systemName: "pin.fill").font(font(.caption2))
                                .opacity(command.isPinned ? 1 : 0)
                        }
                        Text("\(command.totalUseCount.formatted(.number.notation(.compactName)))회")
                            .font(.system(size: u(small ? 8 : 9), weight: .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.foregroundStyle(.secondary).accessibilityHidden(true)
                }
                if small {
                    Text(command.title).font(.system(size: u(9), weight: .medium)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(command.title).font(.system(size: u(12), weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(u(small ? 4 : 10)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }.buttonStyle(TileStyle(section: .menus, emphasized: command.isPinned))
            .help(command.path.joined(separator: " › ") + (command.isPinned ? " · 고정됨" : "") + "\n" + command.usageDescription)
            .accessibilityValue(command.usageDescription)
            .contextMenu {
                Button(command.isPinned ? "고정 해제" : "앞에 고정") {
                    settings.togglePin(command.id)
                    editedMenus = MenuCommand.ordered(settings.commands, appID: command.appID, history: settings.menuHistory)
                }
                Button("목록에서 삭제하고 자동 수집 제외") {
                    settings.removeCommand(command)
                    editedMenus = MenuCommand.ordered(settings.commands, appID: command.appID, history: settings.menuHistory)
                }
            }
            .environment(\.tileColors, colors)
    }

    private var registeredSection: some View {
        let grid = RegisteredGridGeometry(width: snapshot.layout.contentSize.width, scale: snapshot.layout.scale)
        return VStack(alignment: .leading, spacing: DeckSpacing.sectionTitle) {
            HStack(spacing: 8) {
                sectionTitle("등록 항목", symbol: "square.grid.2x2")
                profilePicker
                Text("\(registeredItems.count)개").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("\(snapshot.shortcuts.registeredPrefix)1–0").font(.caption).foregroundStyle(.secondary)
                Button { showSettings(.registered) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("앱·폴더 추가 및 순서 변경")
            }.frame(height: 26)
            if registeredItems.isEmpty {
                Button("앱이나 폴더 추가") { showSettings(.registered) }
                    .buttonStyle(.borderless).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(grid.side), spacing: grid.gap), count: grid.columns),
                              spacing: grid.gap) {
                        ForEach(Array(registeredItems.enumerated()), id: \.element.id) { index, pin in
                            Button { selectPin(pin) } label: {
                                if startTileLabels {
                                    ZStack(alignment: .bottomLeading) {
                                        Group {
                                            if pin.kind == .trash { Image(systemName: "trash").font(.system(size: u(34))) }
                                            else { Icon(url: pin.url, size: 36) }
                                        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, u(14))
                                        Text(pin.name).font(.system(size: u(9), weight: .medium)).lineLimit(1).padding(u(5))
                                    }.frame(width: grid.side, height: grid.side)
                                        .overlay(alignment: .topTrailing) { numberBadge(index).padding(u(3)) }
                                } else {
                                VStack(spacing: u(4)) {
                                    Group {
                                        if pin.kind == .trash {
                                            Image(systemName: "trash").font(.system(size: u(28))).frame(width: u(32), height: u(32))
                                        } else { Icon(url: pin.url, size: 32) }
                                    }
                                    Text(pin.name).font(.system(size: u(10), weight: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                }.padding(u(6)).frame(width: grid.side, height: grid.side)
                                    .overlay(alignment: .topTrailing) { numberBadge(index).padding(u(3)) }
                                }
                            }.buttonStyle(RegisteredTileStyle(selected: presentation.selection == "pin:\(pin.id)" || presentation.execution?.target == "pin:\(pin.id)",
                                                              emphasized: pin.kind == .app))
                                .disabled(pin.kind == .app && launches.isBlocked(pin.url))
                                .overlay {
                                    if pin.kind == .app && launches.isBlocked(pin.url) { ApplicationLaunchBusy() }
                                }
                                .accessibilityValue(pin.kind == .app && launches.isBlocked(pin.url) ? "실행 중, 잠시 기다려 주세요" : "")
                                .help(pinHelp(pin, index: index))
                                .accessibilityLabel(pinHelp(pin, index: index))
                        }
                    }.padding(.top, 4)
                }.id(presentation.profile?.id ?? snapshot.profileID)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var profilePicker: some View {
        Menu {
            Button("집중 모드에 따라 자동 선택") { changeProfile(nil) }
            Divider()
            ForEach(settings.profiles) { profile in
                Button(profile.name) { changeProfile(profile.id) }
            }
        } label: {
            Label(profileName, systemImage: "circle.dotted")
                .font(.caption).lineLimit(1).frame(maxWidth: 110)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 8).frame(height: 26)
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("프로필 선택 · ⌥A/S 이전 · ⌥D/F 다음 · 키/휠 임시 전환은 닫으면 복귀")
        .accessibilityAction(named: Text("이전 프로필")) { cycleProfile(-1) }
        .accessibilityAction(named: Text("다음 프로필")) { cycleProfile(1) }
    }
    private func pinHelp(_ pin: PinnedItem, index: Int) -> String {
        let shortcut = NumberShortcutAssignment.digit(for: index).map { " · \(snapshot.shortcuts.registeredPrefix)\($0)" } ?? ""
        return pin.name + shortcut + (pin.kind == .trash ? " · 통합 휴지통은 Finder에서만 열 수 있습니다." : "")
    }
    @ViewBuilder private func numberBadge(_ index: Int, side: CGFloat = 16) -> some View {
        if let digit = NumberShortcutAssignment.digit(for: index) {
            Text(digit).font(.system(size: u(side == 16 ? 10 : 8), weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: u(side), height: u(side)).background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .accessibilityHidden(true)
        }
    }
    private func recentSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DeckSpacing.sectionTitle) {
            HStack(spacing: 8) {
                sectionTitle("최근 창", symbol: "rectangle.on.rectangle")
                Text("\(snapshot.windows.count)개").font(.caption2).foregroundStyle(.tertiary)
                if let previewRecentLegend {
                    Text(previewRecentLegend).font(.caption2).foregroundStyle(.secondary)
                } else if recentAppearance == .locationColor {
                    RecentWindowLegend()
                }
                Spacer(minLength: 4)
                Text("\(snapshot.shortcuts.windowPrefix)1–0").font(.caption).foregroundStyle(.secondary)
            }.frame(height: 20)
            if !snapshot.permission {
                VStack(spacing: u(8)) {
                    Text("창을 보여주려면 접근성 권한이 필요해요.").font(font(.callout))
                    Button("접근성 허용하기", action: requestPermission).buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot.windows.isEmpty {
                Text("열린 창을 확인하고 있어요.\n잠시 후 다시 열어 주세요.")
                    .font(font(.callout)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let columns = previewDesktopColumns, let sizes = previewWindowSizes {
                DesktopColumnsPreview(data: columns, sizes: sizes, width: columns.preferredWidth ?? geometry.windowWidth) { index, size in
                    windowTile(snapshot.windows[index], index: index, wide: size == .wide, small: size == .application)
                }
            } else {
                let identities = snapshot.windows.map(\.appKey)
                // Location, first appearances and numbered targets all use the
                // same snapshot while Option is held.
                let sizes = previewWindowSizes ?? (recentAppearance == .locationColor
                    ? snapshot.windows.map { $0.isApplication ? .application : $0.location.size }
                    : recentAppearance == .grouped
                    ? GroupedRecentWindows.sizes(apps: identities, applications: snapshot.windows.map(\.isApplication),
                                                 desktops: snapshot.windows.map(\.desktop),
                                                 activeApp: OverlayContent.activeAppKey(snapshot.context, in: snapshot.windows))
                    : recentAppearance == .squares ? snapshot.windows.map { $0.isApplication ? RecentTileSize.application : .square }
                    : RecentTileArrangement.sizes(apps: identities, applications: snapshot.windows.map(\.isApplication),
                                                 consecutiveSmall: recentAppearance == .consecutiveSmall))
                let packed = RecentTileArrangement.place(sizes: sizes, columns: geometry.windowColumns * 2)
                let firstIDs = firstWindowIDs
                // The scroll offset lives in its own view: scrolling re-evaluates only
                // the visible recent tiles, not the menus and registered grid.
                RecentTileScroll(placements: packed, module: (geometry.unit - geometry.gap) / 2, gap: geometry.gap,
                                 width: geometry.windowWidth,
                                 viewport: max(0, height - DeckSpacing.workHeader(scale: snapshot.layout.scale))) { place in
                    windowTile(snapshot.windows[place.index], index: place.index, wide: place.width == 4,
                               small: place.height == 1, firstIDs: firstIDs)
                }
                // A new window list starts at the top with a fresh offset.
                .id(snapshot.windows.map(\.id))
            }
        }.frame(height: height)
    }
    /// Unclipped version of the same comparison for reviewing every app group.
    @ViewBuilder var desktopColumnDetails: some View {
        if let columns = previewDesktopColumns, let sizes = previewWindowSizes {
            DesktopColumnsPreview(data: columns, sizes: sizes, width: columns.preferredWidth ?? geometry.windowWidth, expanded: true) { index, size in
                windowTile(snapshot.windows[index], index: index, wide: size == .wide, small: size == .application)
            }
            .environment(\.deckTheme, settings.theme)
            .environment(\.tileColors, settings.tileColors)
        }
    }
    private func windowTile(_ window: WindowItem, index: Int, wide: Bool, small: Bool = false,
                            firstIDs: Set<UUID>? = nil) -> some View {
        let desktop = window.isApplication ? .unknown : presentation.windowDesktops[window.id] ?? .unknown
        let locationDescription: String = recentAppearance == .locationColor ? {
            switch window.location {
            case .activeDisplay: "활성 모니터의 보이는 데스크탑"
            case .otherVisibleDisplay: "다른 모니터의 보이는 데스크탑"
            case .hidden: "보이지 않는 데스크탑"
            case .visibleUnknownDisplay: "보이는 데스크탑 · 모니터 확인 안 됨"
            case .unknown: "데스크탑 확인 안 됨"
            }
        }() : desktop == .current ? "현재 데스크탑" : desktop == .other ? "다른 데스크탑" : "데스크탑 확인 안 됨"
        let emphasized = previewEmphasizedWindows?.contains(window.id)
            ?? (recentAppearance == .locationColor ? (firstIDs ?? firstWindowIDs).contains(window.id) : desktop == .current)
        var colors = settings.tileColors
        if window.isApplication && recentAppearance.neutralApplications { colors.windows = TileColor(0x777777) }
        let palette = DeckPalette(section: .windows, emphasized: emphasized,
                                  dark: deckScheme == .dark, theme: settings.theme, colors: colors)
        return Button { selectWindow(window) } label: {
            Group {
              if startTileLabels {
                let compactTile = window.isApplication || small
                ZStack(alignment: .bottomLeading) {
                    Icon(url: window.appURL, size: compactTile ? 26 : 58)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: compactTile && NumberShortcutAssignment.digit(for: index) != nil ? .leading : .center)
                        .padding(.leading, u(compactTile ? 3 : 0))
                        .padding(.bottom, u(compactTile ? 12 : 22))
                    Text(window.isApplication ? window.appName : window.title)
                        .font(.system(size: u(compactTile ? 8 : 12), weight: .medium)).lineLimit(1)
                        .padding(u(compactTile ? 3 : 8))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
              } else if previewLargeWindowIcons {
                if window.isApplication || small {
                    VStack(alignment: .leading, spacing: u(1)) {
                        Icon(url: window.appURL, size: 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(window.isApplication ? window.appName : window.title)
                            .font(.system(size: u(8.5), weight: .medium)).lineLimit(1)
                    }.padding(u(3)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if previewBalancedWindowLabels {
                    VStack(spacing: u(6)) {
                        Icon(url: window.appURL, size: 42).frame(maxWidth: .infinity)
                        Text(window.title).font(.system(size: u(11), weight: .medium)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: u(28), alignment: .topLeading)
                    }.padding(u(8)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: u(0)) {
                        Icon(url: window.appURL, size: 42).frame(maxWidth: .infinity)
                        Spacer(minLength: u(4))
                        Text(window.title).font(.system(size: u(11), weight: .medium)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(u(8)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
              } else if window.isApplication || small {
                VStack(alignment: .leading, spacing: u(2)) {
                    Icon(url: window.appURL, size: 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(window.isApplication ? window.appName : window.title).font(.system(size: u(9), weight: .medium)).lineLimit(1)
                }.padding(u(4)).frame(maxWidth: .infinity, maxHeight: .infinity)
              } else {
                VStack(alignment: .leading, spacing: u(5)) {
                HStack(spacing: u(5)) {
                    Icon(url: window.appURL, size: 22)
                    if wide || recentAppearance.uniform { Text(window.appName).font(font(.caption2)).foregroundStyle(palette.secondary).lineLimit(1) }
                    Spacer(minLength: u(0))
                }.padding(.trailing, u(12))
                Text(window.title).font(.system(size: u(12), weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(u(10)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
              }
            }
                .overlay(alignment: .topTrailing) {
                    if startTileLabels && (small || window.isApplication) {
                        numberBadge(index, side: 12).padding(u(2))
                    } else {
                        numberBadge(index).padding(u(previewLargeWindowIcons && (small || window.isApplication) ? 2 : 5))
                    }
                }
        }.buttonStyle(TileStyle(section: .windows, emphasized: emphasized,
                                selected: presentation.selection == "window:\(window.id)" || presentation.execution?.target == "window:\(window.id)", compact: small || window.isApplication))
            .disabled(window.isApplication && window.appURL.map(launches.isBlocked) == true)
            .overlay {
                if window.isApplication && window.appURL.map(launches.isBlocked) == true { ApplicationLaunchBusy(compact: true) }
            }
            .help(window.isApplication ? "\(window.appName) · 열린 창 없음 · 앱 활성화" : "\(window.appName) — \(window.title)" + (window.minimized ? " · 최소화됨" : "")
                + " · " + locationDescription)
            .accessibilityLabel(window.isApplication ? "\(index + 1). \(window.appName), 열린 창 없음" : "\(index + 1). \(window.appName), \(window.title), \(locationDescription)" + (recentAppearance == .locationColor ? (emphasized ? ", 앱별 최근 창" : ", 같은 앱의 다른 창") : ""))
            .contextMenu {
                if window.isApplication {
                    Button("\(window.appName) 종료") { quitApplication(window) }
                }
            }
            .environment(\.tileColors, colors)
    }

    private var folderContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Picker("정렬", selection: $browser.sort) {
                    ForEach(FolderSort.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 160)
                    .help("추가 날짜가 없는 파일은 생성일로 정렬합니다.")
                Spacer()
                Button("Finder에서 열기") { if let url = browser.current { openInFinder(url) } }
                    .buttonStyle(.borderless)
                Button(action: browser.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("새로고침")
            }
            if browser.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = browser.error {
                ContentUnavailableView("폴더 접근이 필요해요", systemImage: "folder.badge.questionmark",
                                       description: Text(error))
            } else if browser.entries.isEmpty {
                ContentUnavailableView("비어 있는 폴더", systemImage: "folder")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: u(108)), spacing: u(12))], spacing: u(12)) {
                        ForEach(browser.entries) { entry in
                            Button {
                                if entry.directory { browser.enter(entry) } else { openURL(entry.url) }
                            } label: {
                                VStack(spacing: u(9)) {
                                    Icon(url: entry.url, size: 42)
                                    Text(entry.name).font(font(.caption1)).lineLimit(2).multilineTextAlignment(.center)
                                }.padding(u(10)).frame(maxWidth: .infinity).frame(height: u(108))
                            }.buttonStyle(TileStyle(section: .registered)).help(entry.name)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func sectionTitle(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.caption) }
            Text(title).font(.system(size: 12, weight: .semibold))
        }.foregroundStyle(.secondary)
    }
}

/// Virtualized recent-window area. Owns the scroll offset so a scroll frame
/// only re-runs this body; `tile` builds just the placements in view.
private struct RecentTileScroll<Tile: View>: View {
    let placements: [RecentTilePlacement]
    let module: CGFloat
    let gap: CGFloat
    let width: CGFloat
    let viewport: CGFloat
    @ViewBuilder let tile: (RecentTilePlacement) -> Tile
    @State private var offset: CGFloat = 0
    var body: some View {
        let bottom = placements.map { $0.row + $0.height }.max() ?? 0
        let visible = RecentTileArrangement.visible(placements, module: module, gap: gap, offset: offset, viewport: viewport)
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                ForEach(visible, id: \.index) { place in
                    tile(place)
                        .frame(width: module * CGFloat(place.width) + gap * CGFloat(place.width - 1),
                               height: module * CGFloat(place.height) + gap * CGFloat(place.height - 1))
                        .offset(x: CGFloat(place.column) * (module + gap), y: CGFloat(place.row) * (module + gap))
                }
            }.frame(width: width, height: CGFloat(bottom) * module + CGFloat(max(0, bottom - 1)) * gap, alignment: .topLeading)
        }
        .onScrollGeometryChange(for: CGFloat.self) { value in max(0, value.visibleRect.minY) }
        action: { _, value in offset = value }
        .scrollIndicators(.visible)
    }
}
