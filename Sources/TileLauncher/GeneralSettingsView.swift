import AppKit
import SwiftUI
import DeckCore

struct GeneralSettingsView: View {
    let settings: SettingsStore
    let loginItem: LoginItemManager
    let requestPermission: () -> Void
    let openAppManagementSettings: () -> Void
    var body: some View {
        ScrollView {
            GeneralSettingsContent(settings: settings, loginItem: loginItem,
                                   requestPermission: requestPermission, openAppManagementSettings: openAppManagementSettings)
        }.scrollIndicators(.visible)
    }
}

/// Shared by the scrollable tab and its initial-window height measurement.
struct GeneralSettingsContent: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemManager
    let requestPermission: () -> Void
    let openAppManagementSettings: () -> Void
    @State private var countText = ""
    @State private var invalidCount = false
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.footerGap) {
            VStack(alignment: .leading, spacing: SettingsSpacing.sectionGap) {
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
                        Text("1–9, 0으로 선택하고 Option을 놓으면 실행합니다. 0은 10번째이며 등록 항목 번호는 현재 프로필을 따릅니다.")
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
                        Text("최근 사용한 창부터 표시합니다. 최대 3.3줄을 보여주며 아래로 스크롤할 수 있습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        RecentWindowExplanation()
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                PermissionsSettingsSection(requestPermission: requestPermission, openAppManagementSettings: openAppManagementSettings)
            }
            Text(AppIdentity.versionLabel).font(.caption).foregroundStyle(.secondary)
        }.modifier(SettingsPaneInsets()).fixedSize(horizontal: false, vertical: true)
        .onAppear { countText = String(settings.manualCount); loginItem.refresh() }
    }
    private func saveCount() {
        guard let value = Int(countText.trimmingCharacters(in: .whitespaces)), value >= 6 else { invalidCount = true; return }
        invalidCount = false; settings.manualCount = value
    }
}
