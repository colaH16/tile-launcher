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
private struct TileStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(configuration.isPressed ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
struct DeckView: View {
    let snapshot: OverlaySnapshot
    @ObservedObject var settings: SettingsStore
    @ObservedObject var browser: FolderBrowser
    @ObservedObject var presentation: OverlayPresentation
    let selectApp: (AppItem) -> Void
    let selectPin: (PinnedItem) -> Void
    let selectMenu: (MenuCommand) -> Void
    let changeProfile: (String?) -> Void
    @State private var editedMenus: [MenuCommand]?
    let selectWindow: (WindowItem) -> Void
    let openURL: (URL) -> Void
    let openInFinder: (URL) -> Void
    let openTrash: () -> Void
    let showSettings: () -> Void
    let requestPermission: () -> Void
    let dismiss: () -> Void
    private var compact: Bool { snapshot.layout.compact }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: compact ? 10 : 18) {
                if browser.current != nil {
                    folderContents
                } else {
                    GeometryReader { area in
                        let content = DeckContentLayout(width: snapshot.layout.frame.width,
                                                        availableHeight: area.size.height,
                                                        registeredCount: snapshot.pins.count, compact: compact)
                        VStack(spacing: 0) {
                            workArea.padding(.top, content.workTopInset)
                            Spacer(minLength: content.gap)
                            registeredSection.frame(height: content.registeredHeight)
                        }
                    }
                }
                HStack {
                    Image(systemName: presentation.isPinned ? "pin.fill" : "option")
                    Text(presentation.isPinned ? "상단의 빈 곳을 드래그하여 이동 · Esc 닫기" : "놓으면 닫기 · ⌥X 고정 · ⌘, 설정").font(.caption)
                    Spacer()
                    Text("Tile Launcher").font(.caption).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(.horizontal, 138)
            .allowsHitTesting(false)

            HStack(spacing: 8) {
                Button {
                    if presentation.isPinned { dismiss() } else { presentation.pin() }
                } label: {
                    Image(systemName: presentation.isPinned ? "xmark" : "pin")
                        .frame(width: 34, height: 34).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .help(presentation.isPinned ? "닫기 · Esc 또는 ⌘W" : "창 고정 · ⌥X · Option을 놓아도 유지")
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
                HStack(spacing: 10) {
                    Menu {
                        Button("집중 모드에 따라 자동 선택") { changeProfile(nil) }
                        Divider()
                        ForEach(settings.profiles) { profile in
                            Button(profile.name) { changeProfile(profile.id) }
                        }
                    } label: {
                        Label(snapshot.profileName, systemImage: "circle.dotted")
                            .font(.caption).lineLimit(1).frame(maxWidth: 90)
                    }.menuStyle(.borderlessButton).fixedSize()
                        .help("등록 항목 프로필 선택")
                    Divider().frame(height: 16)
                    Button(action: showSettings) {
                        Image(systemName: "slider.horizontal.3").frame(width: 28, height: 30)
                    }
                    .buttonStyle(.plain).help("설정 · ⌘,")
                    .accessibilityLabel("설정")
                }
                .padding(.horizontal, 10).frame(height: 36)
                .glassEffect(.regular, in: Capsule())
                .anchorPreference(key: HeaderControlsKey.self, value: .bounds) { [$0] }
            }
        }
        .frame(height: compact ? 40 : 52)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, compact ? 10 : 18)
        .overlayPreferenceValue(HeaderControlsKey.self) { controls in
            GeometryReader { geometry in
                OverlayDragHandle(enabled: presentation.isPinned,
                                  excludedRects: controls.map { geometry[$0] })
                    .allowsHitTesting(presentation.isPinned)
            }
        }
    }

    private var headerTitle: String {
        guard let current = browser.current else { return snapshot.context?.name ?? "Tile Launcher" }
        return browser.path.count == 1 ? browser.rootName : current.lastPathComponent
    }
    private var headerSubtitle: String {
        if browser.current != nil { return browser.path.count == 1 ? "등록한 폴더" : browser.rootName }
        return snapshot.contextWindowTitle ?? "지금 하던 일에서, 다음으로"
    }

    private var geometry: DeckGeometry { DeckGeometry(width: snapshot.layout.frame.width, compact: compact) }
    private var menuItems: [MenuCommand] { editedMenus ?? snapshot.commands }
    private var workArea: some View {
        HStack(alignment: .top, spacing: 22) {
            if !compact { menuSection.frame(width: geometry.menuWidth) }
            recentSection.frame(width: geometry.windowWidth)
        }
    }
    private func rows(_ spans: [Int], columns: Int) -> [[TilePlacement]] {
        let placements = TileArrangement.place(spans: spans, columns: columns)
        return (0..<(placements.last.map { $0.row + 1 } ?? 0)).map { row in placements.filter { $0.row == row } }
    }
    private func tileWidth(_ span: Int) -> CGFloat { geometry.unit * CGFloat(span) + geometry.gap * CGFloat(span - 1) }

    private var menuSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("메뉴", symbol: "command")
                Spacer()
                Button(action: showSettings) { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("설정에서 앱별 메뉴 추가")
            }.frame(height: 20)
            if menuItems.isEmpty {
                Button(action: showSettings) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "command").font(.title2)
                        Text("앱별 메뉴 추가").font(.callout.weight(.medium))
                        Text("설정 → 메뉴에서 자주 쓰는 동작을 등록하세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }.buttonStyle(TileStyle())
            } else {
                let packed = rows(menuItems.map { $0.isWide ? 2 : 1 }, columns: 4)
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
        }.frame(height: geometry.twoRows + 30)
    }
    private func menuTile(_ command: MenuCommand) -> some View {
        Button { selectMenu(command) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "command").font(.system(size: 20))
                    Spacer(minLength: 0)
                    if command.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(command.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(command.isPinned ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(TileStyle())
            .help(command.path.joined(separator: " › ") + (command.isPinned ? " · 고정됨" : ""))
            .contextMenu {
                Button(command.isPinned ? "고정 해제" : "앞에 고정") {
                    settings.togglePin(command.id)
                    editedMenus = MenuCommand.ordered(settings.commands, appID: command.appID)
                }
            }
    }

    private var registeredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("등록 항목", symbol: "square.grid.2x2")
                Text("\(snapshot.pins.count)개").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("\(snapshot.shortcuts.registeredPrefix)1–0").font(.caption).foregroundStyle(.secondary)
                Button(action: showSettings) { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("앱·폴더 추가 및 순서 변경")
            }.frame(height: 20)
            if snapshot.pins.isEmpty {
                Button("앱이나 폴더 추가", action: showSettings)
                    .buttonStyle(.borderless).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 8)], spacing: 8) {
                        ForEach(Array(snapshot.pins.enumerated()), id: \.element.id) { index, pin in
                            Button { selectPin(pin) } label: {
                                VStack(spacing: 5) {
                                    Group {
                                        if pin.kind == .trash {
                                            Image(systemName: "trash").font(.system(size: 28)).frame(width: 32, height: 32)
                                        } else { Icon(url: pin.url, size: 32) }
                                    }.overlay(alignment: .topTrailing) {
                                        numberBadge(index).offset(x: 8, y: -4)
                                    }
                                    Text(pin.name).font(.caption2).lineLimit(1).truncationMode(.middle)
                                }.padding(.top, 6).frame(maxWidth: .infinity).frame(height: 60)
                                    .background(presentation.selection == "pin:\(pin.id)" ? Color.accentColor.opacity(0.2) : .clear,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .help(pinHelp(pin, index: index))
                                .accessibilityLabel(pinHelp(pin, index: index))
                        }
                    }.padding(.top, 4)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func pinHelp(_ pin: PinnedItem, index: Int) -> String {
        let shortcut = NumberShortcutAssignment.digit(for: index).map { " · \(snapshot.shortcuts.registeredPrefix)\($0)" } ?? ""
        return pin.name + shortcut + (pin.kind == .trash ? " · 통합 휴지통은 Finder에서만 열 수 있습니다." : "")
    }
    @ViewBuilder private func numberBadge(_ index: Int) -> some View {
        if let digit = NumberShortcutAssignment.digit(for: index) {
            Text(digit).font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                .frame(width: 16, height: 16).background(.regularMaterial, in: Circle())
                .accessibilityHidden(true)
        }
    }
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("최근 창", symbol: "rectangle.on.rectangle")
                Text("\(snapshot.windows.count)개").font(.caption2).foregroundStyle(.tertiary)
                Circle().fill(Color.accentColor.opacity(0.65)).frame(width: 5, height: 5)
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
                let spans = TileArrangement.spans(for: snapshot.windows.map { $0.appURL?.path ?? String($0.pid) })
                let packed = rows(spans, columns: geometry.windowColumns)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: geometry.gap) {
                        ForEach(packed.indices, id: \.self) { row in
                            HStack(spacing: geometry.gap) {
                                ForEach(packed[row], id: \.index) { place in
                                    windowTile(snapshot.windows[place.index], index: place.index, wide: place.span == 2)
                                        .frame(width: tileWidth(place.span), height: geometry.unit)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }.scrollIndicators(.visible)
            }
        }.frame(height: geometry.twoRows + 30)
    }
    private func windowTile(_ window: WindowItem, index: Int, wide: Bool) -> some View {
        let desktop = presentation.windowDesktops[window.id] ?? .unknown
        return Button { selectWindow(window) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Icon(url: window.appURL, size: 22)
                    if wide { Text(window.appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                }.padding(.trailing, 12)
                Text(window.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(presentation.selection == "window:\(window.id)" ? Color.accentColor.opacity(0.3)
                            : desktop == .current ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) { numberBadge(index).padding(5) }
        }.buttonStyle(TileStyle())
            .help("\(window.appName) — \(window.title)" + (window.minimized ? " · 최소화됨" : "")
                + (desktop == .current ? " · 현재 데스크탑" : desktop == .other ? " · 다른 데스크탑" : " · 데스크탑 확인 안 됨"))
            .accessibilityLabel("\(index + 1). \(window.appName), \(window.title)" + (desktop == .current ? ", 현재 데스크탑" : desktop == .other ? ", 다른 데스크탑" : ""))
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
                            }.buttonStyle(TileStyle()).help(entry.name)
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
