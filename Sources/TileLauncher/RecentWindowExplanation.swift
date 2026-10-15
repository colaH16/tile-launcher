import SwiftUI

struct RecentWindowLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            item("현재 모니터", width: 12, height: 6,
                 help: "직사각 타일: 활성 앱이 있는 모니터의 현재 데스크탑")
            item("다른 모니터", width: 7, height: 7,
                 help: "큰 정사각 타일: 다른 모니터에서 현재 보이는 데스크탑")
            item("안 보임", width: 4, height: 4,
                 help: "작은 정사각 타일: 보이지 않는 데스크탑의 창. 회색 작은 타일은 창 없는 앱입니다.")
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
    private func item(_ label: String, width: CGFloat, height: CGFloat, help: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().frame(width: width, height: height)
                .frame(width: 12, height: 10).accessibilityHidden(true)
            Text(label).lineLimit(1)
        }.fixedSize().help(help).accessibilityLabel(help)
    }
}

struct RecentWindowExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("직사각형 · 활성 모니터의 현재 데스크탑")
            Text("큰 정사각형 · 다른 모니터에서 보이는 데스크탑")
            Text("작은 정사각형 · 보이지 않는 데스크탑")
            Text("진한색 · 대표 창(앱에서 마지막으로 사용) / 파스텔 · 같은 앱의 이전 창").padding(.top, 4)
            Text("회색 작은 타일 · 창 없이 실행 중인 앱")
        }.font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
