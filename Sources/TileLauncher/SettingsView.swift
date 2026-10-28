import AppKit
import SwiftUI
import DeckCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var navigation: SettingsNavigation
    let requestPermission: () -> Void
    let openAppManagementSettings: () -> Void
    var applicationProvider: (() -> [AppItem])? = nil
    @StateObject private var editor: SettingsEditingSession
    @State private var profileName = ""

    init(settings: SettingsStore, loginItem: LoginItemManager, navigation: SettingsNavigation,
         requestPermission: @escaping () -> Void, openAppManagementSettings: @escaping () -> Void,
         applicationProvider: (() -> [AppItem])? = nil, editor: SettingsEditingSession? = nil) {
        self.settings = settings; self.loginItem = loginItem; self.navigation = navigation
        self.requestPermission = requestPermission; self.openAppManagementSettings = openAppManagementSettings
        self.applicationProvider = applicationProvider
        _editor = StateObject(wrappedValue: editor ?? SettingsEditingSession(source: settings))
    }
    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $navigation.tab) {
                GeneralSettingsView(settings: settings, loginItem: loginItem,
                                    requestPermission: requestPermission, openAppManagementSettings: openAppManagementSettings)
                    .tabItem { Label("일반", systemImage: "gearshape") }.tag(SettingsTab.general)
                SettingsEditorPane(session: editor, draft: editor.appearance, tab: .appearance) { draft in
                    VStack(alignment: .leading, spacing: 0) {
                        Label("iCloud 동기화 대상", systemImage: "icloud").font(.caption).foregroundStyle(.secondary).padding(.horizontal, SettingsSpacing.paneInset)
                        AppearanceView(settings: draft)
                    }
                }.tabItem { Label("모양", systemImage: "paintpalette") }.tag(SettingsTab.appearance)
                SettingsEditorPane(session: editor, draft: editor.menus, tab: .menus) { draft in
                    MenuSettingsView(settings: draft, preferredApp: navigation.preferredApp, additionRequest: navigation.menuAddition,
                                     additionSize: MenuAdditionLayout.size(for: geometry.size), applicationProvider: applicationProvider)
                }
                    .tabItem { Label("메뉴", systemImage: "command") }.tag(SettingsTab.menus)
                SettingsEditorPane(session: editor, draft: editor.registered, tab: .registered, onCancel: { profileName = "" }) { draft in
                    registeredPane(settings: draft)
                }.tabItem { Label("등록 항목·프로필", systemImage: "square.grid.2x2") }.tag(SettingsTab.registered)
            }.padding(SettingsWindowLayout.outerPadding)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
        }
        .onAppear { editor.activate(); settings.syncStatus.setSettingsVisible?(true); settings.syncStatus.refresh?() }
        .sheet(item: Binding(get: { editor.registered.dockImportPreview }, set: { editor.registered.dockImportPreview = $0 }),
               onDismiss: editor.registered.cancelDockImport) { change in
            DockImportPreview(change: change, apply: { editor.registered.applyDockImport(change) },
                              cancel: editor.registered.cancelDockImport)
        }
        .onDisappear { editor.registered.cancelDockImport(); editor.pause(); settings.syncStatus.setSettingsVisible?(false) }
    }
    private func registeredPane(settings: SettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("이 Mac에만 저장 · iCloud 동기화 안 함", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
            GroupBox("프로필") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("구성", selection: Binding(get: { settings.activeProfile.id }, set: settings.selectProfile)) {
                            ForEach(settings.profiles) { Text($0.name).tag($0.id) }
                        }
                        Button("프로필 삭제", action: settings.removeActiveProfile)
                            .disabled(settings.activeProfile.id == "default" || settings.profiles.count < 2)
                            .help("이 프로필의 등록만 삭제합니다. 앱과 파일은 삭제하지 않습니다.")
                    }
                    HStack {
                        TextField("새 프로필 이름", text: $profileName)
                        Button("빈 프로필 추가") {
                            settings.addProfile(name: profileName, copyingCurrent: false)
                            profileName = ""
                        }
                        .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("현재 구성을 복제") {
                            settings.addProfile(name: profileName, copyingCurrent: true)
                            profileName = ""
                        }
                            .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Toggle("집중 모드 필터에 따라 프로필 자동 선택", isOn: $settings.followFocus)
                    DisclosureGroup("프로필 순서") {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(settings.profiles) { profile in
                                    HStack {
                                        Text(profile.name).lineLimit(1)
                                        Spacer()
                                        Button { settings.moveProfile(profile.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                            .disabled(settings.profiles.first?.id == profile.id)
                                            .help("\(profile.name) 앞으로 이동").accessibilityLabel("\(profile.name) 앞으로 이동")
                                        Button { settings.moveProfile(profile.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                            .disabled(settings.profiles.last?.id == profile.id)
                                            .help("\(profile.name) 뒤로 이동").accessibilityLabel("\(profile.name) 뒤로 이동")
                                    }
                                }
                            }.padding(4)
                        }.frame(height: min(112, CGFloat(settings.profiles.count) * 30))
                    }
                    Text("왼쪽으로 쓸면 다음, 오른쪽으로 쓸면 이전 프로필입니다. 이 순서대로 순환하며, 오버레이를 닫으면 임시 선택은 해제됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("시스템 설정 → 집중 모드 → 앱 필터에서 Tile Launcher와 프로필을 연결하세요. 필터가 없거나 해제되면 수동으로 선택한 구성으로 돌아갑니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            HStack {
                Text("등록 앱·폴더").font(.headline)
                Spacer()
                Button(settings.importingDock ? "가져오는 중…" : "Dock에서 가져오기", action: settings.importDock)
                    .disabled(settings.importingDock)
                Menu {
                    Button("앱 추가…", action: settings.addApplications)
                    Button("폴더 추가…", action: settings.addFolder)
                    Button("다운로드 추가") {
                        settings.addFolderURL(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0], name: "다운로드")
                    }
                    Button("휴지통 추가") {
                        settings.addFolderURL(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"), kind: .trash, name: "휴지통")
                    }
                } label: { Label("추가", systemImage: "plus") }.fixedSize()
            }
            if settings.dockImportMessage != nil || settings.canUndoDockImport {
                HStack(alignment: .top) {
                    if let message = settings.dockImportMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if settings.canUndoDockImport {
                        Button("가져오기 되돌리기", action: settings.undoDockImport)
                            .controlSize(.small).fixedSize()
                            .help("이 프로필의 다른 등록 항목을 수정하거나 앱을 종료하기 전까지 되돌릴 수 있습니다.")
                    }
                }
            }
            List {
                ForEach(settings.pins) { pin in
                    HStack {
                        if pin.kind == .trash { Image(systemName: "trash").font(.system(size: 24)).frame(width: 28, height: 28) }
                        else { Icon(url: pin.url, size: 28) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pin.name).lineLimit(1).truncationMode(.middle)
                            if pin.kind == .trash {
                                Text("휴지통은 Finder에서만 열 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                            } else if pin.kind == .app { Text("앱").font(.caption).foregroundStyle(.secondary) }
                            else {
                                Picker("여는 방식", selection: Binding(get: { pin.openMode }, set: { settings.setOpenMode($0, for: pin.id) })) {
                                    ForEach(FolderOpenMode.allCases) { Text($0.title).tag($0) }
                                }.labelsHidden().pickerStyle(.menu).fixedSize().accessibilityLabel("\(pin.name) 여는 방식")
                            }
                        }
                        Spacer()
                        Button { settings.move(pin, by: -1) } label: { Image(systemName: "chevron.up") }
                            .help("앞으로 이동").disabled(settings.pins.first == pin)
                        Button { settings.move(pin, by: 1) } label: { Image(systemName: "chevron.down") }
                            .help("뒤로 이동").disabled(settings.pins.last == pin)
                        Button { settings.pins.removeAll { $0.id == pin.id } } label: { Image(systemName: "minus.circle") }.help("등록 해제")
                    }.buttonStyle(.borderless).padding(.vertical, 4)
                }.onMove { settings.pins.move(fromOffsets: $0, toOffset: $1) }
            }.overlay {
                if settings.pins.isEmpty { Text("추가 버튼으로 앱과 폴더를 등록하세요.").foregroundStyle(.secondary) }
            }.frame(minHeight: 150)
            Text("앞의 10개에 1–9, 0이 표시됩니다. 순서를 바꾸면 숫자도 바뀝니다.").font(.caption).foregroundStyle(.secondary)
        }.modifier(SettingsPaneInsets())
    }

}

struct MenuSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let preferredApp: AppItem?
    let additionRequest: MenuAdditionRequest?
    let additionSize: CGSize
    var applicationProvider: (() -> [AppItem])? = nil
    @StateObject private var catalog = MenuCatalog()
    @State private var applications: [AppItem] = []
    @State private var selectedID = ""
    @State private var search = ""
    @State private var manualPath = ""
    @State private var showingAddition = false
    @State private var handledRequestID: UUID?
    @State private var configurationHeight: CGFloat = 360
    init(settings: SettingsStore, preferredApp: AppItem?, additionRequest: MenuAdditionRequest?,
         additionSize: CGSize, applicationProvider: (() -> [AppItem])? = nil) {
        self.settings = settings
        self.preferredApp = preferredApp
        self.additionRequest = additionRequest
        self.additionSize = additionSize
        self.applicationProvider = applicationProvider
        // Start with the known app so the table does not replace all its groups
        // from inside its initial AppKit row/layout callbacks.
        _selectedID = State(initialValue: preferredApp?.id ?? "")
    }
    private var selectedApp: AppItem? { applications.first { $0.id == selectedID } }
    private var appNames: [(id: String, name: String)] {
        var names = Dictionary(settings.commands.map { ($0.appID, $0.appName) }, uniquingKeysWith: { first, _ in first })
        applications.forEach { names[$0.id] = $0.name }
        if let preferredApp { names[preferredApp.id] = preferredApp.name }
        for id in settings.menuCapture.excludedApps where names[id] == nil {
            names[id] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
        }
        return names.map { (id: $0.key, name: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    configuration
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { content in
                            Color.clear.preference(key: MenuConfigurationHeight.self, value: content.size.height)
                        })
                }
                .scrollIndicators(.visible)
                .frame(height: min(configurationHeight, max(120, geometry.size.height - 230)))
                .onPreferenceChange(MenuConfigurationHeight.self) { height in
                    if height > 0, abs(height - configurationHeight) > 0.5 { configurationHeight = height }
                }
                savedMenus.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    HStack {
                        SyncEditingGate(status: settings.syncStatus) { Button("메뉴 추가…") { beginAddition(app: nil) } }
                        Spacer()
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.modifier(SettingsPaneInsets())
        .task {
            // Defer dynamic app/group changes until the initial table layout has
            // returned, including when there is no known preferred app.
            await Task.yield()
            guard !Task.isCancelled else { return }
            refreshApps()
            handleAdditionRequest()
        }
        .onChange(of: selectedID) { _, value in settings.syncStatus.checkMenus?(value) }
        .onChange(of: additionRequest?.id) { _, _ in handleAdditionRequest() }
        .onChange(of: settings.menuRecentDaysInput) { _, _ in settings.updateMenuHistoryInput() }
        .onChange(of: settings.menuFrequentDaysInput) { _, _ in settings.updateMenuHistoryInput() }
        .sheet(isPresented: $showingAddition) {
            MenuAdditionSheet(settings: settings, catalog: catalog, selectedID: $selectedID,
                              search: $search, manualPath: $manualPath, appNames: appNames,
                              selectedApp: selectedApp, size: additionSize,
                              refreshApps: {
                                  refreshApps()
                                  if let app = selectedApp { catalog.load(app: app) }
                              }, dismiss: { showingAddition = false })
                .task(id: selectedID) {
                    if let app = selectedApp { catalog.load(app: app) } else { catalog.clear() }
                }
                .onDisappear { catalog.clear() }
        }
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("공통 메뉴") {
                VStack(alignment: .leading, spacing: 8) {
                    SyncEditingGate(status: settings.syncStatus) { Toggle("앱 설정 타일 표시", isOn: $settings.showAppSettingsTile) }
                    Text("자동 수집과 별개로, 설정 메뉴를 지원하는 앱에 타일을 표시합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("자동 메뉴 수집 · 실험 기능") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("모든 앱의 메뉴 막대에서 선택한 메뉴 수집", isOn: $settings.menuCapture.enabled)
                    Text("메뉴 막대에서 직접 선택한 메뉴를 기록합니다. 일부 앱에서는 수집이 누락될 수 있습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("최근·자주 사용 기간") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("최근 사용")
                        TextField("30", text: $settings.menuRecentDaysInput).frame(width: 70).accessibilityLabel("최근 사용 기간, 일")
                        Text("일 또는 앱별 최근 5개")
                    }
                    HStack {
                        Text("자주 사용")
                        TextField("90", text: $settings.menuFrequentDaysInput).frame(width: 70).accessibilityLabel("자주 사용 기간, 일")
                        Text("일 안에 3회 이상")
                        Spacer()
                    }
                    if settings.validMenuHistoryInput == nil { Text("기간은 1–36,500일로 입력해 주세요.").font(.caption).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            HStack {
                Picker("앱", selection: $selectedID) {
                    if selectedID.isEmpty { Text("앱 선택").tag("") }
                    ForEach(appNames, id: \.id) { Text($0.name).tag($0.id) }
                }
                Button("앱 목록 새로고침", action: refreshApps)
            }
            if !selectedID.isEmpty {
                Toggle("이 앱의 자동 수집 중단", isOn: Binding(get: {
                    settings.menuCapture.excludedApps.contains(selectedID)
                }, set: { excluded in
                    if excluded { settings.menuCapture.excludedApps.insert(selectedID) }
                    else { settings.menuCapture.excludedApps.remove(selectedID) }
                }))
                Text(!settings.menuCapture.enabled ? "전체 자동 수집이 꺼져 있습니다."
                     : settings.menuCapture.excludedApps.contains(selectedID) ? "이 앱의 수집을 중단했습니다."
                     : settings.menuCaptureStatus[selectedID] ?? "이 앱을 사용할 때 메뉴 수집 지원 여부를 확인합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("자동 수집 목록 비우기") { settings.clearCapturedMenus(appID: selectedID) }
                        .help("이 앱의 고정하지 않은 자동 수집 메뉴만 지웁니다. 다음 메뉴 선택은 다시 수집합니다.")
                    Button("숨긴 메뉴 다시 수집") {
                        settings.menuCapture.excludedMenus = settings.menuCapture.excludedMenus.filter { $0.appID != selectedID }
                    }.disabled(!settings.menuCapture.excludedMenus.contains { $0.appID == selectedID })
                }
            }
            DisclosureGroup("수집과 표시 안내") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("메뉴 클릭과 열린 메뉴·Help 검색의 Enter 선택을 기록합니다. Apple 로고의 시스템 메뉴 전체, 단축키 직접 실행, 리본·우클릭 메뉴는 제외합니다. 복사·붙여넣기도 메뉴에서 선택했다면 수집합니다.")
                    Text("앱이 메뉴 정보를 제공하지 않으면 일부 선택이 누락될 수 있습니다. 검색어·입력 문자는 저장하지 않습니다.")
                    Text("기간이 지나고 최근 5개에서도 벗어난 메뉴만 최근 목록에서 숨깁니다. 고정 메뉴는 유지하며, 아래 목록에서 다시 고정할 수 있습니다.")
                    Text("고정 메뉴는 맨 앞의 강조색 가로형(4×2), 자주 사용은 파스텔 정사각형(2×2), 최근 사용은 회색 정사각형(2×2)입니다. 자주 사용은 설정한 기간 안에 런처 실행과 메뉴 선택을 합쳐 3회 이상인 메뉴입니다.")
                    Text("메뉴 추가 시 앱 리소스의 아이콘을 저장합니다. 없으면 이미 읽은 다른 앱에서 이름이 같은 메뉴를 찾습니다. 앱 업데이트 후에도 유지하며 아래 버튼으로 다시 가져옵니다. 직접 지정한 아이콘은 우선합니다. 리소스에 메뉴와 아이콘의 연결이 없는 앱은 지원하지 않습니다.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var savedMenus: some View {
        let commands = MenuCommand.ordered(settings.commands, appID: selectedID, history: settings.menuHistory, includingHidden: true)
        let pinned = commands.filter(\.isPinned)
        let collected = commands.filter { !$0.isPinned }
        let moves = MenuCommand.pinnedMoveTargets(in: settings.commands)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("자동 수집·고정 메뉴 \(commands.count)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(settings.refreshingMenuIcons.contains(selectedID) ? "아이콘 확인 중…" : "메뉴 아이콘 새로고침") {
                    settings.onRefreshMenuIcons?(selectedID)
                }.controlSize(.small)
                    .disabled(commands.isEmpty || settings.refreshingMenuIcons.contains(selectedID))
                    .help("선택한 앱의 메뉴 아이콘을 다시 가져옵니다. 직접 지정한 아이콘은 유지합니다.")
            }
            if let status = settings.menuIconStatus[selectedID] {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            List {
                ForEach(menuRows(pinned: pinned, collected: collected)) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        switch row {
                        case .pinnedHeading:
                            MenuGroupHeading(title: "고정", symbol: "pin.fill", count: pinned.count, detail: "직접 순서 변경")
                        case .emptyPinned:
                            Text("메뉴 오른쪽 핀을 누르면 이곳에 표시됩니다.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        case .divider:
                            Divider().padding(.vertical, 12)
                        case .collectedHeading:
                            MenuGroupHeading(title: "자동 수집", symbol: "clock.arrow.circlepath", count: collected.count,
                                             detail: "사용 횟수 많은 순")
                        case .emptyCollected:
                            Text("자동 수집된 메뉴가 없습니다.").font(.caption).foregroundStyle(.secondary)
                        case .command(let command):
                            savedMenuRow(command, moves: moves[command.id])
                        }
                    }.listRowSeparator(.hidden)
                }
            }.listStyle(.plain)
        }
    }
    private func menuRows(pinned: [MenuCommand], collected: [MenuCommand]) -> [MenuSettingsRow] {
        [.pinnedHeading] + (pinned.isEmpty ? [.emptyPinned] : pinned.map(MenuSettingsRow.command))
            + [.divider, .collectedHeading]
            + (collected.isEmpty ? [.emptyCollected] : collected.map(MenuSettingsRow.command))
    }
    private func savedMenuRow(_ command: MenuCommand, moves: MenuCommand.MoveTargets?) -> some View {
        HStack {
            // The icon basis is taken by the first actual choice (setSymbol),
            // not by opening the picker.
            MenuGlyphButton(command: command) { settings.setSymbol($0, for: command.id) }
            VStack(alignment: .leading, spacing: 3) {
                MenuCommandDetails(command: command, history: settings.menuHistory)
                    .strikethrough(settings.unavailableMenus.contains(command.id))
                if settings.unavailableMenus.contains(command.id) {
                    Text("이 Mac의 앱에 없는 메뉴 · 데이터는 보존됩니다").font(.caption).foregroundStyle(.secondary)
                }
                if settings.sharedMenus.contains(command.id) {
                    Label("iCloud 동기화 대상", systemImage: "icloud").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { settings.togglePin(command.id) } label: {
                Image(systemName: command.isPinned ? "pin.fill" : "pin")
            }.help(command.isPinned ? "고정 해제" : "앞에 고정")
                .accessibilityLabel("\(command.title) \(command.isPinned ? "고정 해제" : "앞에 고정")")
            if command.isPinned {
                Button { settings.moveCommand(command.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(moves?.previous == nil).help("고정 메뉴 안에서 앞으로 이동")
                    .accessibilityLabel("\(command.title) 앞으로 이동")
                Button { settings.moveCommand(command.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(moves?.next == nil).help("고정 메뉴 안에서 뒤로 이동")
                    .accessibilityLabel("\(command.title) 뒤로 이동")
            }
            Button { settings.removeCommand(command) } label: { Image(systemName: "minus.circle") }
                .help("목록에서 삭제하고 자동 수집에서도 제외")
        }.buttonStyle(.borderless)
        .modifier(SyncMenuRowLock(status: settings.syncStatus))
    }
    private func beginAddition(app: AppItem?) {
        refreshApps()
        if let app { selectedID = app.id }
        search = ""
        manualPath = ""
        showingAddition = true
    }
    private func handleAdditionRequest() {
        guard let request = additionRequest else {
            showingAddition = false
            return
        }
        guard request.id != handledRequestID else { return }
        handledRequestID = request.id
        beginAddition(app: request.app)
    }
    private func refreshApps() {
        settings.syncStatus.checkMenus?(selectedID)
        applications = applicationProvider?() ?? NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in
                guard let id = app.bundleIdentifier ?? app.bundleURL?.path else { return nil }
                return AppItem(id: id, pid: app.processIdentifier, name: app.localizedName ?? id, url: app.bundleURL)
            }
        if selectedID.isEmpty { selectedID = preferredApp?.id ?? applications.first?.id ?? settings.commands.first?.appID ?? "" }
    }
}

private struct MenuConfigurationHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Shared by the real settings list and the isolated native preview.
struct MenuCommandDetails: View {
    let command: MenuCommand
    var history: MenuHistoryPreferences? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(command.title)
            Text(command.path.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
            Text(usageDescription).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if command.isAutomatic && MenuCapturePolicy.isAppleMenuPath(command.path) {
                Text("Apple 시스템 메뉴 · 자동 수집 제외 · 고정하지 않으면 오버레이에서 숨김")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var usageDescription: String {
        guard let history, !command.isPinned else { return command.usageDescription }
        let category = command.isFrequent(history: history) ? "자주 사용" : "최근 사용"
        return "\(category) · \(command.usageDescription)"
    }

}

struct MenuGroupHeading: View {
    let title: String
    let symbol: String
    let count: Int
    let detail: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title).fontWeight(.semibold)
            Text("\(count)개")
            Spacer()
            Text(detail)
        }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
    }
}

/// Give AppKit one stable, explicit row sequence even when a menu changes groups.
private enum MenuSettingsRow: Identifiable {
    case pinnedHeading, emptyPinned, divider, collectedHeading, emptyCollected
    case command(MenuCommand)
    var id: String {
        switch self {
        case .pinnedHeading: return "pinned-heading"
        case .emptyPinned: return "empty-pinned"
        case .divider: return "divider"
        case .collectedHeading: return "collected-heading"
        case .emptyCollected: return "empty-collected"
        case .command(let command): return "menu-" + command.id.uuidString
        }
    }
}
