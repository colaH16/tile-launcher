import DeckCore
import SwiftUI

struct SettingsSyncControls: View {
    @ObservedObject var status: SettingsSyncStatus
    @State private var showsScope = false
    var body: some View {
        GroupBox("iCloud 동기화") {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Toggle("이 Mac에서 iCloud 동기화", isOn: Binding(get: { status.enabled }, set: { status.setEnabled?($0) }))
                    Button("동기화 항목") { showsScope = true }.font(.caption)
                        .popover(isPresented: $showsScope) { scope.padding(16).frame(width: 380) }
                }
                if status.enabled { HStack {
                    if status.locked && status.initialConflicts.isEmpty { ProgressView().controlSize(.small) }
                    Text(status.message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if status.enabled && !status.awaitingAccount {
                        Button("지금 동기화") { status.refresh?() }.disabled(status.locked)
                    }
                } }
                if let error = status.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                if !status.initialConflicts.isEmpty {
                    Text("2.0 이전 설정 중 수정 시각이 없는 \(status.initialConflicts.count)개 항목의 값이 다릅니다. 충돌 없는 항목은 병합합니다.")
                        .font(.callout)
                    Text(status.initialConflicts.map(Self.conflictName).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("iCloud 값 사용") { status.chooseInitial?(false) }
                        Button("이 Mac 값 업로드") { status.chooseInitial?(true) }
                    }
                }
                if !status.iconConflicts.isEmpty { SettingsSyncIconChoices(status: status) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
    private var scope: some View {
        VStack(alignment: .leading, spacing: 10) {
                Text("동기화: 모양 · 직접 추가하거나 편집한 메뉴 · 고정/순서/아이콘 · 앱 설정 타일 표시 · Option 재입력 보정 · 숫자 단축키 · 최근 창 개수")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("이 Mac에만 저장: 등록 앱·폴더·프로필 · 자동 수집 설정과 사용 기록 · 로그인 항목 · 권한")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private static func conflictName(_ key: String) -> String {
        let names = ["theme": "테마", "showAppSettings": "앱 설정 타일 표시", "menuColor": "메뉴 색",
                     "windowColor": "최근 창 색", "handoffColor": "Handoff 색", "registeredColor": "등록 항목 색",
                     "reopenEnabled": "Option 재입력 보정", "reopenInterval": "재입력 허용 시간",
                     "numberShortcuts": "숫자 단축키", "automaticWindowCount": "최근 창 자동 배치",
                     "manualWindowCount": "최근 창 개수"]
        if key.hasPrefix("pref:") { return names[String(key.dropFirst(5))] ?? "설정" }
        return key.hasPrefix("pin:") ? "메뉴 고정 여부" : "고정 메뉴 순서"
    }

}

struct SettingsSyncIconChoices: View {
    @ObservedObject var status: SettingsSyncStatus
    var body: some View {
        DisclosureGroup("아이콘 선택 필요 · \(status.iconConflicts.count)개") {
            ForEach(status.iconConflicts) { menu in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(menu.appName) · \(menu.path.joined(separator: " › "))").font(.caption)
                    HStack {
                        ForEach(Array(Set(menu.icon.edits.compactMap { $0.symbol })).sorted(), id: \.self) { symbol in
                            Button {
                                status.chooseIcon?(menu.id, symbol)
                            } label: {
                                if symbol == MenuSymbolName.hidden { Text("아이콘 없음") }
                                else { Label(symbol, systemImage: symbol) }
                            }
                        }
                        if menu.icon.edits.contains(where: { $0.symbol == nil }) {
                            Button("기본 아이콘") { status.chooseIcon?(menu.id, nil) }
                        }
                    }
                }.padding(.vertical, 4)
            }
        }
    }
}

struct SyncEditingGate<Content: View>: View {
    @ObservedObject var status: SettingsSyncStatus
    var gated: Bool = true
    @ViewBuilder var content: () -> Content
    var body: some View { content().disabled(gated && status.locked) }
}

struct SyncMenuRowLock: ViewModifier {
    @ObservedObject var status: SettingsSyncStatus
    func body(content: Content) -> some View { content.disabled(status.locked) }
}
