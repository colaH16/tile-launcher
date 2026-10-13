import SwiftUI
import DeckCore

struct OptionReopenSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        GroupBox("Option 재입력 보정") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("빠르게 다시 누르면 닫힌 위치에서 열기", isOn: Binding(
                    get: { settings.optionReopen.enabled },
                    set: { settings.optionReopen = .init(enabled: $0, interval: settings.optionReopen.interval) }
                ))
                Stepper(value: Binding(
                    get: { settings.optionReopen.interval },
                    set: { settings.optionReopen = .init(enabled: settings.optionReopen.enabled,
                                                        interval: ($0 * 10).rounded() / 10) }
                ), in: OptionReopenPreferences.intervalRange, step: 0.1) {
                    Text("다시 누를 수 있는 시간: \(settings.optionReopen.interval, specifier: "%.1f")초")
                        .monospacedDigit()
                }
                .disabled(!settings.optionReopen.enabled)
                Text("Option을 놓으면 바로 닫힙니다. 설정한 시간 안에 다시 누르면 이전 위치로 즉시 열립니다. 기본 0.6초 · 0.1–2.0초 조절")
                    .font(.caption).foregroundStyle(.secondary)
                Text("항목을 실행했거나 닫기·Esc를 누른 경우, 그 사이 다른 키를 누르거나 클릭한 경우에는 적용하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }.disabled(!settings.optionTriggerEnabled)
    }
}
