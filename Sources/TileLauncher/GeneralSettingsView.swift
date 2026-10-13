import AppKit
import SwiftUI
import DeckCore

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemManager
    @State private var countText = ""
    @State private var invalidCount = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                Text(AppIdentity.versionLabel).font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        .scrollIndicators(.visible)
        .onAppear { countText = String(settings.manualCount); loginItem.refresh() }
    }
    private func saveCount() {
        guard let value = Int(countText.trimmingCharacters(in: .whitespaces)), value >= 6 else { invalidCount = true; return }
        invalidCount = false; settings.manualCount = value
    }
}
