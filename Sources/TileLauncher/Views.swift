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
    var body: some View {
        Image(nsImage: AppIconCache.shared.icon(url)).resizable().interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
private struct RegisteredTileStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected)
    }
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.deckTheme) private var theme
        @Environment(\.tileColors) private var colors
        @State private var hovering = false
        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: theme.isClassic ? 0 : 12, style: .continuous) }
        var body: some View {
            let palette = DeckPalette(section: .registered, dark: scheme == .dark, theme: theme, colors: colors)
            configuration.label
                .foregroundStyle(palette.ink, palette.secondary)
                .contentShape(shape)
                .background(palette.fill.opacity(theme.isClassic || reduceTransparency ? 1 : 0.96), in: shape)
                .overlay {
                    shape.fill(Color.accentColor.opacity(selected || configuration.isPressed ? 0.18 : hovering ? 0.07 : 0))
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(selected ? Color.accentColor.opacity(0.65)
                                       : Color.primary.opacity(contrast == .increased ? 0.5 : hovering ? 0.22 : 0.12),
                                       lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .onHover { hovering = $0 }
        }
    }
}
private struct TileStyle: ButtonStyle {
    var section: TileSection = .menus
    var emphasized = false
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, section: section, emphasized: emphasized, selected: selected)
    }
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let section: TileSection
        let emphasized: Bool
        let selected: Bool
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.deckTheme) private var theme
        @Environment(\.tileColors) private var colors
        @State private var hovering = false
        var body: some View {
            let palette = DeckPalette(section: section, emphasized: emphasized, dark: scheme == .dark, theme: theme, colors: colors)
            let shape = RoundedRectangle(cornerRadius: theme.isClassic ? 0 : 14, style: .continuous)
            configuration.label
                .foregroundStyle(palette.ink, palette.secondary)
                .contentShape(shape)
                .background {
                    ZStack {
                        shape.fill(palette.fill.opacity(theme.isClassic || reduceTransparency ? 1 : 0.96))
                        shape.fill(palette.ink.opacity(configuration.isPressed ? 0.16 : hovering ? 0.10 : 0))
                    }.allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(selected || configuration.isPressed ? Color.accentColor
                                       : palette.ink.opacity(hovering ? 0.65 : contrast == .increased ? 0.55 : 0.08),
                                       lineWidth: selected || configuration.isPressed || hovering ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .onHover { hovering = $0 }
        }
    }
}
struct DeckView: View {
    @ObservedObject var content: OverlayContent
    private var snapshot: OverlaySnapshot { content.snapshot }
    @ObservedObject var settings: SettingsStore
    @ObservedObject var browser: FolderBrowser
    @ObservedObject var presentation: OverlayPresentation
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
    var resizeForProfile: (Int) -> Void = { _ in }
    var quitApplication: (WindowItem) -> Void = { _ in }
    let dismiss: () -> Void
    private var compact: Bool { snapshot.layout.compact }
    private var registeredItems: [PinnedItem] { presentation.profile?.items ?? snapshot.pins }
    private var profileName: String { presentation.profile?.name ?? snapshot.profileName }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var deckScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: DeckSpacing.sections(compact: compact)) {
                if browser.current != nil {
                    folderContents
                } else {
                    GeometryReader { area in
                        let content = DeckContentLayout(width: snapshot.layout.frame.width,
                                                        availableHeight: area.size.height,
                                                        registeredCount: registeredItems.count, compact: compact)
                        VStack(spacing: 0) {
                            workArea(height: content.workHeight)
                            Color.clear.frame(height: content.gap)
                            registeredSection.frame(height: content.registeredHeight)
                            Spacer(minLength: 0)
                        }
                    }
                }
                HStack {
                    Image(systemName: presentation.isPinned ? "pin.fill" : "option")
                    Text(compact ? "⌥X 고정 · ⌥W 닫기 · ⌥, 설정"
                         : presentation.isPinned ? "상단 드래그로 이동 · ⌥W 닫기 · ⌥, 설정" : "놓으면 닫기 · ⌥X 고정 · ⌥, 설정")
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Text(compact ? "⌥A/S ← · ⌥D/F →" : "⌥A/S 이전 · ⌥D/F 다음")
                        .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
                .frame(height: 18)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DeckSpacing.edge)
            .padding(.bottom, DeckSpacing.edge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.deckTheme, settings.theme)
        .environment(\.tileColors, settings.tileColors)
        .background {
            // The AppKit surface clips this fill and the native glass together.
            Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : 0.28)
        }
        .onChange(of: snapshot.commands) { _, _ in editedMenus = nil }
        .onChange(of: registeredItems.count) { _, count in resizeForProfile(count) }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: compact ? 18 : 23, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(headerSubtitle).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 104)
            .allowsHitTesting(false)

            HStack(spacing: 8) {
                Button {
                    if presentation.isPinned { dismiss() } else { pinOverlay() }
                } label: {
                    Image(systemName: presentation.isPinned ? "xmark" : "pin")
                        .frame(width: 34, height: 34).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .help(presentation.isPinned ? "닫기 · Esc · ⌘W · ⌥W" : "창 고정 · ⌥X · Option을 놓아도 유지")
                .accessibilityLabel(presentation.isPinned ? "고정된 오버레이 닫기" : "오버레이 고정")
                .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }

                if browser.current != nil {
                    Button(action: browser.back) {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .help("뒤로")
                    .accessibilityLabel("이전 폴더로 이동")
                    .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }
                }
                Spacer()
                Button { showSettings(.general) } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 34, height: 34).contentShape(Circle())
                }
                .buttonStyle(.plain).help("설정 · ⌘, 또는 ⌥,")
                .accessibilityLabel("설정")
                .glassEffect(.regular.interactive(), in: Circle())
                .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }
            }
        }
        .frame(height: compact ? 40 : 52)
        .padding(.horizontal, DeckSpacing.edge)
        .padding(.top, DeckSpacing.edge)
        .padding(.bottom, DeckSpacing.sections(compact: compact))
        .overlayPreferenceValue(HeaderControlsKey.self) { controls in
            GeometryReader { geometry in
                OverlayDragHandle(enabled: presentation.isPinned,
                                  excludedRects: controls.map { geometry[$0] })
                    .allowsHitTesting(presentation.isPinned)
            }
        }
    }

    private var headerTitle: String {
        guard let current = browser.current else { return snapshot.context?.name ?? AppIdentity.name }
        return browser.path.count == 1 ? browser.rootName : current.lastPathComponent
    }
    private var headerSubtitle: String {
        if browser.current != nil { return browser.path.count == 1 ? "등록한 폴더" : browser.rootName }
        return snapshot.contextWindowTitle ?? "지금 하던 일에서, 다음으로"
    }

    private var geometry: DeckGeometry { DeckGeometry(width: snapshot.layout.frame.width, compact: compact) }
    private var menuItems: [MenuCommand] { editedMenus ?? snapshot.commands }
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
            HStack {
                sectionTitle("메뉴", symbol: "command")
                Spacer()
                Button { showSettings(.addMenu) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("설정에서 앱별 메뉴 추가")
            }.frame(height: 20)
            if menuItems.isEmpty {
                Button { showSettings(.addMenu) } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "command").font(.title2)
                        Text("앱별 메뉴 추가").font(.callout.weight(.medium))
                        Text("설정 → 메뉴에서 자주 쓰는 동작을 등록하세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }.buttonStyle(TileStyle())
            } else {
                let packed = rows(menuItems.map { ($0.isPinned || snapshot.frequentMenuIDs.contains($0.id)) ? 2 : 1 }, columns: 4)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: geometry.gap) {
                        ForEach(packed.indices, id: \.self) { row in
                            HStack(spacing: geometry.gap) {
                                ForEach(packed[row], id: \.index) { place in
                                    menuTile(menuItems[place.index]).frame(width: tileWidth(place.span), height: geometry.unit)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }.scrollIndicators(.visible)
            }
        }.frame(height: height)
    }
    private func menuTile(_ command: MenuCommand) -> some View {
        Button { selectMenu(command, snapshot.context, snapshot.windows.first { $0.pid == snapshot.context?.pid }) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Image(systemName: "command").font(.system(size: 20))
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Image(systemName: "pin.fill").font(.caption2)
                            .opacity(command.isPinned ? 1 : 0)
                        Text("\(command.totalUseCount.formatted(.number.notation(.compactName)))회")
                            .font(.system(size: 9, weight: .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(command.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
    }

    private var registeredSection: some View {
        let grid = RegisteredGridGeometry(width: snapshot.layout.frame.width)
        return VStack(alignment: .leading, spacing: DeckSpacing.sectionTitle) {
            HStack {
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
                                VStack(spacing: 4) {
                                    Group {
                                        if pin.kind == .trash {
                                            Image(systemName: "trash").font(.system(size: 28)).frame(width: 32, height: 32)
                                        } else { Icon(url: pin.url, size: 32) }
                                    }
                                    Text(pin.name).font(.system(size: 10, weight: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                }.padding(6).frame(width: grid.side, height: grid.side)
                                    .overlay(alignment: .topTrailing) { numberBadge(index).padding(3) }
                            }.buttonStyle(RegisteredTileStyle(selected: presentation.selection == "pin:\(pin.id)"))
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
    @ViewBuilder private func numberBadge(_ index: Int) -> some View {
        if let digit = NumberShortcutAssignment.digit(for: index) {
            Text(digit).font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 16, height: 16).background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .accessibilityHidden(true)
        }
    }
    private func recentSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DeckSpacing.sectionTitle) {
            HStack {
                sectionTitle("최근 창", symbol: "rectangle.on.rectangle")
                Text("\(snapshot.windows.count)개").font(.caption2).foregroundStyle(.tertiary)
                Circle().fill(settings.tileColors.seed(for: .windows, theme: settings.theme).swiftUIColor).frame(width: 5, height: 5)
                Text("현재 데스크탑").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(snapshot.shortcuts.windowPrefix)1–0").font(.caption).foregroundStyle(.secondary)
            }.frame(height: 20)
            if !snapshot.permission {
                VStack(spacing: 8) {
                    Text("창을 보여주려면 접근성 권한이 필요해요.").font(.callout)
                    Button("접근성 허용하기", action: requestPermission).buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot.windows.isEmpty {
                Text("열린 창을 확인하고 있어요.\n잠시 후 다시 열어 주세요.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let sizes = RecentTileArrangement.sizes(apps: snapshot.windows.map { $0.appURL?.path ?? String($0.pid) },
                                                        applications: snapshot.windows.map(\.isApplication))
                let packed = RecentTileArrangement.place(sizes: sizes, columns: geometry.windowColumns * 2)
                let micro = (geometry.unit - geometry.gap) / 2
                let bottom = packed.map { $0.row + $0.height }.max() ?? 0
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        ForEach(packed, id: \.index) { place in
                            windowTile(snapshot.windows[place.index], index: place.index, wide: place.width == 4)
                                .frame(width: micro * CGFloat(place.width) + geometry.gap * CGFloat(place.width - 1),
                                       height: micro * CGFloat(place.height) + geometry.gap * CGFloat(place.height - 1))
                                .offset(x: CGFloat(place.column) * (micro + geometry.gap),
                                        y: CGFloat(place.row) * (micro + geometry.gap))
                        }
                    }.frame(width: geometry.windowWidth,
                            height: CGFloat(bottom) * micro + CGFloat(max(0, bottom - 1)) * geometry.gap,
                            alignment: .topLeading)
                }.scrollIndicators(.visible).id(snapshot.windows.map(\.id))
            }
        }.frame(height: height)
    }
    private func windowTile(_ window: WindowItem, index: Int, wide: Bool) -> some View {
        let desktop = window.isApplication ? .unknown : presentation.windowDesktops[window.id] ?? .unknown
        let palette = DeckPalette(section: .windows, emphasized: desktop == .current,
                                  dark: deckScheme == .dark, theme: settings.theme, colors: settings.tileColors)
        return Button { selectWindow(window) } label: {
            Group {
              if window.isApplication {
                VStack(alignment: .leading, spacing: 2) {
                    Icon(url: window.appURL, size: 20).frame(maxWidth: .infinity, alignment: .leading)
                    Text(window.appName).font(.system(size: 9, weight: .medium)).lineLimit(1)
                }.padding(4).frame(maxWidth: .infinity, maxHeight: .infinity)
              } else {
                VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Icon(url: window.appURL, size: 22)
                    if wide { Text(window.appName).font(.caption2).foregroundStyle(palette.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                }.padding(.trailing, 12)
                Text(window.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
              }
            }
                .overlay(alignment: .topTrailing) { numberBadge(index).padding(5) }
        }.buttonStyle(TileStyle(section: .windows, emphasized: desktop == .current,
                                selected: presentation.selection == "window:\(window.id)"))
            .help(window.isApplication ? "\(window.appName) · 열린 창 없음 · 앱 활성화" : "\(window.appName) — \(window.title)" + (window.minimized ? " · 최소화됨" : "")
                + (desktop == .current ? " · 현재 데스크탑" : desktop == .other ? " · 다른 데스크탑" : " · 데스크탑 확인 안 됨"))
            .accessibilityLabel(window.isApplication ? "\(index + 1). \(window.appName), 열린 창 없음" : "\(index + 1). \(window.appName), \(window.title)" + (desktop == .current ? ", 현재 데스크탑" : desktop == .other ? ", 다른 데스크탑" : ""))
            .contextMenu {
                if window.isApplication {
                    Button("\(window.appName) 종료") { quitApplication(window) }
                }
            }
    }

    private var folderContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 12)], spacing: 12) {
                        ForEach(browser.entries) { entry in
                            Button {
                                if entry.directory { browser.enter(entry) } else { openURL(entry.url) }
                            } label: {
                                VStack(spacing: 9) {
                                    Icon(url: entry.url, size: 42)
                                    Text(entry.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }.padding(10).frame(maxWidth: .infinity).frame(height: 108)
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
