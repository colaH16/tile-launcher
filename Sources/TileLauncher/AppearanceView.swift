import SwiftUI
import AppKit
import DeckCore

struct AppearanceView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsSpacing.sectionGap) {
                GroupBox("테마") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("타일 모양", selection: $settings.theme) {
                            ForEach(DeckTheme.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.radioGroup)
                        Text("유리·파스텔은 둥글고 은은하게, 클래식·직각은 각지고 불투명하게 표시합니다. 배경과 상단 버튼은 Liquid Glass를 유지합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text("섹션별 색상").font(.headline)
                Text("선택한 색으로 기본 타일과 강조 타일을 함께 조정합니다. 메뉴 색은 고정·자주 사용에 적용하며 최근 메뉴는 회색으로 구분합니다. 글자색은 읽기 쉽게 자동으로 맞춥니다.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(TileSection.allCases) { section in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ColorPicker(section.title, selection: colorBinding(section), supportsOpacity: false)
                                Button("기본색") { settings.tileColors[section] = nil }
                                    .disabled(settings.tileColors[section] == nil)
                                    .help("\(section.title) 색만 기본값으로 복원")
                            }
                            HStack(spacing: 8) {
                                sample(section == .menus ? "최근 사용" : "기본", section: section, emphasized: false, width: 56, gray: section == .menus)
                                sample(section == .menus ? "자주 사용" : "기본 · 긴 타일",
                                       section: section, emphasized: false, width: section == .menus ? 56 : 120)
                                if section != .registered {
                                    sample(section == .menus ? "고정 메뉴" : "현재 데스크탑",
                                           section: section, emphasized: true, width: 120)
                                }
                                Spacer(minLength: 0)
                            }.accessibilityElement(children: .combine)
                        }.padding(8)
                    }
                }
                Text("직접 고른 색은 테마를 바꿔도 유지됩니다. 기본색에서는 메뉴가 유리 테마의 노랑 / 클래식 테마의 초록, 최근 창은 파랑, 등록 항목은 보라 계열입니다. 메뉴 막대 아이콘은 두 테마 공통입니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("모든 섹션 기본색으로") { settings.tileColors = TileColors() }
                    .disabled(settings.tileColors == TileColors())
            }.modifier(SettingsPaneInsets())
        }
    }
    private func colorBinding(_ section: TileSection) -> Binding<Color> {
        Binding(get: { settings.tileColors.seed(for: section, theme: settings.theme).swiftUIColor },
                set: { if let rgb = TileColor(color: $0) { settings.tileColors[section] = rgb } })
    }
    private func sample(_ title: String, section: TileSection, emphasized: Bool, width: CGFloat, gray: Bool = false) -> some View {
        var colors = settings.tileColors
        if gray { colors[section] = TileColor(0x777777) }
        let palette = DeckPalette(section: section, emphasized: emphasized, dark: scheme == .dark,
                                  theme: settings.theme, colors: colors)
        return VStack(alignment: .leading, spacing: 5) {
            Image(systemName: emphasized && section == .menus ? "pin.fill" : "square.fill")
            Text(title).font(.caption2).lineLimit(2)
        }
        .foregroundStyle(palette.ink).padding(8).frame(width: width, height: 56, alignment: .leading)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: settings.theme.isClassic ? 0 : 10))
    }
}
