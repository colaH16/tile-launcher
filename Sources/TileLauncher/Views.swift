import AppKit
import SwiftUI
import DeckCore

private struct HeaderControlsKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct Icon: View {
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
    let selectWindow: (WindowItem) -> Void
    let openURL: (URL) -> Void
    let openInFinder: (URL) -> Void
    let openTrash: () -> Void
    let showSettings: () -> Void
    let requestPermission: () -> Void
    let dismiss: () -> Void
    private var compact: Bool { snapshot.layout.compact }
    private var tileHeight: CGFloat { compact ? 66 : 82 }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: compact ? 10 : 18) {
                if browser.current != nil {
                    folderContents
                } else {
                    registeredSection.frame(maxHeight: .infinity, alignment: .top)
                    recentSection
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
                    Label("기본", systemImage: "circle.dotted").font(.caption)
                        .help("집중 모드별 프로필은 다음 단계에 추가됩니다.")
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

    private var registeredSection: some View {
        HStack(alignment: .top, spacing: 24) {
            if !compact {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("고정 메뉴", symbol: "pin")
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "command").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                        Text("자주 쓰는 동작을 이 자리에").font(.callout.weight(.medium))
                        Text("앱별 메뉴는 다음 단계에 연결할게요.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("등록 항목", symbol: "square.grid.2x2")
                    Spacer()
                    Button(action: showSettings) { Image(systemName: "plus").font(.callout) }
                        .buttonStyle(.plain).help("앱·폴더 추가 및 순서 변경")
                }
                if settings.pins.isEmpty {
                    Button(action: showSettings) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle").font(.title2)
                            Text("앱이나 폴더 추가").font(.callout)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.buttonStyle(.plain)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                            ForEach(settings.pins) { pin in
                                Button {
                                    if pin.kind == .trash { openTrash() }
                                    else if pin.kind == .app { openURL(pin.url) }
                                    else if pin.opensInOverlay { browser.open(pin) }
                                    else { openInFinder(pin.url) }
                                } label: {
                                    VStack(spacing: 6) {
                                        if pin.kind == .trash {
                                            Image(systemName: "trash").font(.system(size: 28)).frame(height: 34)
                                        } else { Icon(url: pin.url) }
                                        Text(pin.name).font(.caption).lineLimit(1).truncationMode(.middle)
                                    }
                                    .frame(maxWidth: .infinity).frame(height: compact ? 64 : 80)
                                }.buttonStyle(TileStyle())
                                    .help(pin.kind == .trash ? "Dock과 같은 통합 휴지통을 Finder에서 엽니다."
                                          : pin.kind == .app ? pin.name : "\(pin.name) · \(pin.openMode.title)")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: compact ? 72 : 128)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                HStack(spacing: 12) {
                    Text("최근 앱").font(.caption).foregroundStyle(.secondary)
                    ForEach(snapshot.apps) { app in
                        Button { selectApp(app) } label: { Icon(url: app.url, size: 24) }
                            .buttonStyle(.plain).help(app.name)
                    }
                }
            }
            HStack(alignment: .top, spacing: 20) {
                if !compact {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("최근 앱", symbol: nil)
                        ForEach(snapshot.apps) { app in
                            Button { selectApp(app) } label: {
                                HStack(spacing: 6) {
                                    Icon(url: app.url, size: 28)
                                    Text(app.name).font(.caption).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 44)
                            }.buttonStyle(.plain).help(app.name)
                        }
                    }.frame(width: 100, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("최근 창", symbol: "rectangle.on.rectangle")
                        Spacer()
                        Text("\(snapshot.windows.count)개").font(.caption).foregroundStyle(.tertiary)
                    }
                    if !snapshot.permission {
                        VStack(spacing: 10) {
                            Text("창을 보여주려면 접근성 권한이 필요해요.").font(.callout)
                            Button("접근성 허용하기", action: requestPermission).buttonStyle(.borderedProminent)
                            Text("앱·폴더 등록은 지금도 사용할 수 있어요.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: tileHeight * 2 + 10)
                    } else if snapshot.windows.isEmpty {
                        Text("열린 창을 확인하고 있어요.\n잠시 후 다시 열어 주세요.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).frame(height: tileHeight * 2 + 10)
                    } else {
                        ScrollView(.vertical) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                                     count: snapshot.layout.columns), spacing: 10) {
                                ForEach(snapshot.windows) { window in
                                    Button { selectWindow(window) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Icon(url: window.appURL, size: 22)
                                                Text(window.appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                                Spacer(minLength: 0)
                                                if window.minimized { Image(systemName: "minus.square").font(.caption2) }
                                            }
                                            Text(window.title).font(.system(size: 13, weight: .medium))
                                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: tileHeight, alignment: .top)
                                    }
                                    .buttonStyle(TileStyle())
                                    .help("\(window.appName) — \(window.title)")
                                    .accessibilityLabel("\(window.appName), \(window.title)")
                                }
                            }
                        }
                        .frame(height: tileHeight * 2 + 10)
                        .scrollIndicators(.visible)
                    }
                }
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

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemManager
    let requestPermission: () -> Void
    @State private var countText = ""
    @State private var invalidCount = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tile Launcher").font(.title2.weight(.semibold))
            Text("Option을 0.25초 누르면 커서 근처에 열립니다.").foregroundStyle(.secondary).font(.callout)
            GroupBox("시작") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("로그인 시 자동 실행", isOn: Binding(
                        get: { loginItem.registered }, set: { loginItem.setEnabled($0) }))
                        .disabled(loginItem.changing)
                    Text(loginItem.statusText).font(.caption).foregroundStyle(.secondary)
                    if loginItem.needsApproval {
                        Button("로그인 항목 설정 열기", action: loginItem.openSystemSettings)
                    }
                    if let error = loginItem.error {
                        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("최근 창") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("패널 크기에 맞춰 표시 개수 자동 결정", isOn: $settings.automatic)
                    HStack {
                        Text("수동 개수")
                        TextField("최소 6", text: $countText).frame(width: 100)
                            .onSubmit(saveCount)
                        Button("적용", action: saveCount)
                    }.disabled(settings.automatic)
                    if invalidCount { Text("6 이상의 정수를 입력해 주세요.").foregroundStyle(.red).font(.caption) }
                    Text("2줄을 넘는 항목은 최근 창 영역에서 세로로 스크롤합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            HStack {
                Text("등록 앱·폴더").font(.headline)
                Spacer()
                Button(settings.importingDock ? "가져오는 중…" : "Dock에서 가져오기", action: settings.importDock)
                    .disabled(settings.importingDock)
                    .help("고정된 앱·폴더와 Finder·휴지통을 Dock 순서로 가져옵니다. 기존 항목의 설정은 유지합니다.")
                Menu {
                    Button("앱 추가…", action: settings.addApplications)
                    Button("폴더 추가…", action: settings.addFolder)
                    Button("다운로드 추가") {
                        settings.addFolderURL(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
                                              name: "다운로드")
                    }
                    Button("휴지통 추가") {
                        settings.addFolderURL(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),
                                              kind: .trash, name: "휴지통")
                    }
                } label: { Label("추가", systemImage: "plus") }
                .fixedSize()
            }
            if let message = settings.dockImportMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            List {
                ForEach(settings.pins) { pin in
                    HStack {
                        if pin.kind == .trash {
                            Image(systemName: "trash").font(.system(size: 24)).frame(width: 28, height: 28)
                        } else { Icon(url: pin.url, size: 28) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pin.name).lineLimit(1).truncationMode(.middle)
                            if pin.kind == .trash {
                                Text("휴지통은 Finder에서만 열 수 있습니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .help("Dock과 같은 통합 휴지통을 엽니다. 외장 저장소와 ‘되돌려 놓기’는 Finder에서 관리합니다.")
                            } else if pin.kind == .app {
                                Text("앱").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Picker("여는 방식", selection: Binding(
                                    get: { pin.openMode },
                                    set: { settings.setOpenMode($0, for: pin.id) })) {
                                    ForEach(FolderOpenMode.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden().pickerStyle(.menu).fixedSize()
                                .accessibilityLabel("\(pin.name) 여는 방식")
                            }
                        }
                        Spacer()
                        Button { settings.move(pin, by: -1) } label: { Image(systemName: "chevron.up") }
                            .help("앞으로 이동").disabled(settings.pins.first == pin)
                        Button { settings.move(pin, by: 1) } label: { Image(systemName: "chevron.down") }
                            .help("뒤로 이동").disabled(settings.pins.last == pin)
                        Button { settings.pins.removeAll { $0.id == pin.id } } label: { Image(systemName: "minus.circle") }
                            .help("등록 해제")
                    }
                    .buttonStyle(.borderless).padding(.vertical, 4)
                }
                .onMove { settings.pins.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if settings.pins.isEmpty { Text("추가 버튼으로 자주 쓰는 앱과 폴더를 등록하세요.").foregroundStyle(.secondary) }
            }
            .frame(minHeight: 120)
            HStack {
                Button("접근성 권한 설정", action: requestPermission)
                Spacer()
                Text("개인용 개발 버전 0.1").font(.caption).foregroundStyle(.secondary)
            }
            Text("일반 폴더는 여는 방식을 선택할 수 있습니다. 휴지통 보기와 ‘되돌려 놓기’는 Finder에서 이용하세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear { countText = String(settings.manualCount); loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
    private func saveCount() {
        guard let value = Int(countText.trimmingCharacters(in: .whitespaces)), value >= 6 else {
            invalidCount = true
            return
        }
        invalidCount = false
        settings.manualCount = value
    }
}
