import AppKit
import SwiftUI
import DeckCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var navigation: SettingsNavigation
    let requestPermission: () -> Void
    let openAppManagementSettings: () -> Void
    @State private var countText = ""
    @State private var invalidCount = false
    @State private var profileName = ""

    var body: some View {
        TabView(selection: $navigation.tab) {
            general.tabItem { Label("일반", systemImage: "gearshape") }.tag(SettingsTab.general)
            AppearanceView(settings: settings).tabItem { Label("모양", systemImage: "paintpalette") }.tag(SettingsTab.appearance)
            MenuSettingsView(settings: settings, preferredApp: navigation.preferredApp, additionRequest: navigation.menuAddition)
                .tabItem { Label("메뉴", systemImage: "command") }.tag(SettingsTab.menus)
            registered.tabItem { Label("등록 항목·프로필", systemImage: "square.grid.2x2") }.tag(SettingsTab.registered)
        }.padding(16)
            .onAppear { countText = String(settings.manualCount); loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(AppIdentity.name).font(.title2.weight(.semibold))
                Text("Option을 0.25초 누르면 커서 근처에 열립니다.").font(.callout).foregroundStyle(.secondary)
                GroupBox("시작") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Option을 길게 눌러 오버레이 열기", isOn: $settings.optionTriggerEnabled)
                        Toggle("로그인 시 자동 실행", isOn: Binding(get: { loginItem.registered }, set: { loginItem.setEnabled($0) }))
                            .disabled(loginItem.changing)
                        Text(loginItem.statusText).font(.caption).foregroundStyle(.secondary)
                        if loginItem.needsApproval { Button("로그인 항목 설정 열기", action: loginItem.openSystemSettings) }
                        if let error = loginItem.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                OptionReopenSettings(settings: settings)
                GroupBox("숫자 단축키") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("기본 조합", selection: $settings.numberShortcuts) {
                            ForEach(NumberShortcutAssignment.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.radioGroup)
                        Text("오버레이를 연 뒤 1–9, 0으로 첫 10개 중 하나를 고르고 Option을 놓으면 실행합니다. 0은 10번째입니다. 직접 프로필을 넘기면 등록 항목 번호도 해당 목록으로 바뀝니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("⌥X 고정 · ⌘, / ⌥, 설정 · Esc / ⌘W / ⌥W 닫기").font(.caption)
                        Text("⌥A 또는 ⌥S: 이전 프로필 · ⌥D 또는 ⌥F: 다음 프로필").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("최근 창") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("패널 크기에 맞춰 자동 배치 · 전체 창 포함", isOn: $settings.automatic)
                        HStack {
                            Text("수동 최대 개수")
                            TextField("최소 6", text: $countText).frame(width: 100).onSubmit(saveCount)
                            Button("적용", action: saveCount)
                        }.disabled(settings.automatic)
                        if invalidCount { Text("6 이상의 정수를 입력해 주세요.").font(.caption).foregroundStyle(.red) }
                        Text("앱이 바뀌는 곳은 가로형, 같은 앱이 연속되면 정사각형입니다. 현재 데스크탑은 배경색으로 구분합니다. 최대 3.3줄로 다음 줄의 일부까지 보여주며 아래로 스크롤할 수 있습니다. 작은 화면에서는 표시 영역을 줄입니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("권한") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("접근성 권한 설정", action: requestPermission)
                        Text("창 전환과 앱 메뉴 실행·수집에 사용합니다.").font(.caption).foregroundStyle(.secondary)
                        Button("앱 관리 설정 보기", action: openAppManagementSettings)
                        Text("다른 앱을 업데이트·삭제할 수 있는 권한입니다. Tile Launcher에는 해당 기능이 없습니다. 앱 실행 중 이 권한의 차단 알림이 나타날 때 상태를 확인하는 용도로 제공합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text(AppIdentity.versionLabel).font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }
    private var registered: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if let message = settings.dockImportMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
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
        }.padding(16)
    }
    private func saveCount() {
        guard let value = Int(countText.trimmingCharacters(in: .whitespaces)), value >= 6 else { invalidCount = true; return }
        invalidCount = false; settings.manualCount = value
    }
}

struct MenuSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let preferredApp: AppItem?
    let additionRequest: MenuAdditionRequest?
    @StateObject private var catalog = MenuCatalog()
    @State private var applications: [AppItem] = []
    @State private var selectedID = ""
    @State private var search = ""
    @State private var manualPath = ""
    @State private var recentDaysText = ""
    @State private var frequentDaysText = ""
    @State private var invalidHistory = false
    @State private var showingAddition = false
    @State private var handledRequestID: UUID?
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
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("자동 메뉴 수집 · 실험 기능") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("모든 앱의 메뉴 막대에서 선택한 메뉴 수집", isOn: $settings.menuCapture.enabled)
                    Text("메뉴 클릭과 열린 메뉴·Help 검색의 Enter 선택을 기록합니다. Apple 로고의 시스템 메뉴 전체, 단축키 직접 실행, 리본·우클릭 메뉴는 제외합니다. 복사·붙여넣기도 메뉴에서 선택했다면 수집합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("앱이 메뉴 정보를 제공하지 않으면 일부 선택이 누락될 수 있습니다. 검색어·입력 문자는 저장하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("최근·자주 사용 기간") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("최근 사용")
                        TextField("30", text: $recentDaysText).frame(width: 70).accessibilityLabel("최근 사용 기간, 일")
                        Text("일 또는 앱별 최근 5개")
                    }
                    HStack {
                        Text("자주 사용")
                        TextField("90", text: $frequentDaysText).frame(width: 70).accessibilityLabel("자주 사용 기간, 일")
                        Text("일 안에 3회 이상")
                        Spacer()
                        Button("적용", action: saveHistory)
                    }
                    Text("기간이 지나고 최근 5개에서도 벗어난 메뉴만 최근 목록에서 숨깁니다. 고정 메뉴는 유지하며, 아래 목록에서 다시 고정할 수 있습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    if invalidHistory { Text("기간은 1–36,500일로 입력해 주세요.").font(.caption).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.onAppear {
                recentDaysText = String(settings.menuHistory.recentDays)
                frequentDaysText = String(settings.menuHistory.frequentDays)
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
            Text("자동 수집 메뉴는 최근 선택 순으로 표시됩니다. 설정한 자주 사용 기간 안에 런처 실행과 메뉴 선택을 합쳐 3회 이상이면 가로형으로 커지고, 고정 메뉴는 맨 앞에 표시됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(MenuCommand.ordered(settings.commands, appID: selectedID, history: settings.menuHistory, includingHidden: true)) { command in
                    HStack {
                        MenuCommandDetails(command: command)
                        Spacer()
                        Button { settings.togglePin(command.id) } label: {
                            Image(systemName: command.isPinned ? "pin.fill" : "pin")
                        }.help(command.isPinned ? "고정 해제" : "앞에 고정")
                        Button { settings.moveCommand(command.id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(!command.isWide(history: settings.menuHistory)).help("고정·자주 사용 그룹 안에서 앞으로 이동")
                        Button { settings.moveCommand(command.id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(!command.isWide(history: settings.menuHistory)).help("고정·자주 사용 그룹 안에서 뒤로 이동")
                        Button { settings.removeCommand(command) } label: { Image(systemName: "minus.circle") }.help("목록에서 삭제하고 자동 수집에서도 제외")
                    }.buttonStyle(.borderless)
                }
            }.frame(height: 180)
            Divider()
            Button("메뉴 추가…") { beginAddition(app: nil) }
        }.padding(16)
        }.onAppear {
            refreshApps()
            handleAdditionRequest()
        }
        .onChange(of: additionRequest?.id) { _, _ in handleAdditionRequest() }
        .sheet(isPresented: $showingAddition) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("메뉴 추가").font(.title2.weight(.semibold))
                    Spacer()
                    Button("완료") { showingAddition = false }.keyboardShortcut(.cancelAction)
                }
                HStack {
                    Picker("앱", selection: $selectedID) {
                        if selectedID.isEmpty { Text("앱 선택").tag("") }
                        ForEach(appNames, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Button("앱 목록 새로고침") {
                        refreshApps()
                        if let app = selectedApp { catalog.load(app: app) }
                    }
                }
                if selectedApp == nil {
                    Text("메뉴를 추가할 앱을 실행한 뒤 선택해 주세요.").font(.caption).foregroundStyle(.secondary)
                }
                additionForm
            }.padding(20).frame(width: 540)
                .task(id: selectedID) {
                    if let app = selectedApp { catalog.load(app: app) } else { catalog.clear() }
                }
                .onDisappear { catalog.clear() }
        }
    }
    private var additionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("앱의 메뉴 막대에서 선택").font(.headline)
                Spacer()
                Button(catalog.loading ? "읽는 중…" : "선택한 앱의 메뉴 불러오기") {
                    if let app = selectedApp { catalog.load(app: app) }
                }.disabled(selectedApp == nil || catalog.loading)
            }
            TextField("메뉴 검색", text: $search)
            if let message = catalog.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            List {
                ForEach(catalog.choices.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { menu in
                    HStack {
                        Text(menu.title).font(.callout).lineLimit(2)
                        Spacer()
                        let added = settings.commands.contains { $0.appID == selectedID && $0.path == menu.path }
                        Button(added ? "등록됨" : "추가") {
                            if let app = selectedApp { settings.addCommand(MenuCommand(appID: app.id, appName: app.name, path: menu.path)) }
                        }.disabled(added)
                    }
                }
            }.frame(height: 160)
            DisclosureGroup("메뉴 경로 직접 입력") {
                HStack {
                    TextField("예: 파일 > 내보내기 > PDF로 내보내기…", text: $manualPath)
                    Button("추가") {
                        let path = manualPath.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
                        if let app = selectedApp, path.count >= 2, path.allSatisfy({ !$0.isEmpty }) {
                            settings.addCommand(MenuCommand(appID: app.id, appName: app.name, path: path)); manualPath = ""
                        }
                    }.disabled(selectedApp == nil || !manualPath.contains(">"))
                }.padding(.top, 6)
            }
        }
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
    private func saveHistory() {
        guard let recent = Int(recentDaysText.trimmingCharacters(in: .whitespaces)),
              let frequent = Int(frequentDaysText.trimmingCharacters(in: .whitespaces)),
              MenuHistoryPreferences.dayRange.contains(recent), MenuHistoryPreferences.dayRange.contains(frequent) else {
            invalidHistory = true; return
        }
        invalidHistory = false
        settings.menuHistory = MenuHistoryPreferences(recentDays: recent, frequentDays: frequent)
    }
    private func refreshApps() {
        applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in
                guard let id = app.bundleIdentifier ?? app.bundleURL?.path else { return nil }
                return AppItem(id: id, pid: app.processIdentifier, name: app.localizedName ?? id, url: app.bundleURL)
            }
        if selectedID.isEmpty { selectedID = preferredApp?.id ?? applications.first?.id ?? settings.commands.first?.appID ?? "" }
    }
}

/// Shared by the real settings list and the isolated native preview.
struct MenuCommandDetails: View {
    let command: MenuCommand
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(command.title)
            Text(command.path.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
            Text(command.usageDescription).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if command.isAutomatic && MenuCapturePolicy.isAppleMenuPath(command.path) {
                Text("Apple 시스템 메뉴 · 자동 수집 제외 · 고정하지 않으면 오버레이에서 숨김")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
