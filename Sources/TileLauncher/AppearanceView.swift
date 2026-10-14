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
                            HStack(alignment: .top, spacing: 8) {
                                sectionSamples(section)
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
    @ViewBuilder private func sectionSamples(_ section: TileSection) -> some View {
        switch section {
        case .menus:
            sample("최근 사용", section: section, emphasized: false, width: 56, gray: true)
            sample("자주 사용", section: section, emphasized: false, width: 56)
            sample("고정 메뉴", section: section, emphasized: true, width: 120)
        case .windows:
            smallWindowSample()
            sample("반복 앱", section: section, emphasized: false, width: 56).help("목록에 이미 나온 앱의 다른 창 · 크기는 데스크탑 위치 기준")
            sample("첫 등장", section: section, emphasized: true, width: 56).help("최근 창 목록에서 해당 앱의 첫 창 · 크기는 데스크탑 위치 기준")
        case .registered:
            sample("폴더", section: section, emphasized: false, width: 56, symbol: "folder.fill")
            sample("앱", section: section, emphasized: true, width: 56, symbol: "app.fill")
        }
    }
    private func smallWindowSample() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sample("", section: .windows, emphasized: false, width: 24, height: 24, gray: true)
            Text("회색\n1×1").font(.caption2).foregroundStyle(.secondary)
        }.frame(width: 56, alignment: .leading).help("창 없는 앱")
    }
    private func sample(_ title: String, section: TileSection, emphasized: Bool, width: CGFloat,
                        height: CGFloat = 56, gray: Bool = false, symbol: String? = nil) -> some View {
        var colors = settings.tileColors
        if gray { colors[section] = TileColor(0x777777) }
        let palette = DeckPalette(section: section, emphasized: emphasized, dark: scheme == .dark,
                                  theme: settings.theme, colors: colors)
        return VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol ?? (emphasized && section == .menus ? "pin.fill" : "square.fill"))
                .font(height < 56 ? .caption2 : .body)
            if !title.isEmpty { Text(title).font(.caption2).lineLimit(2) }
        }
        .foregroundStyle(palette.ink).padding(height < 56 ? 4 : 8)
        .frame(width: width, height: height, alignment: .leading)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: settings.theme.isClassic ? 0 : min(10, height / 2)))
    }
}
