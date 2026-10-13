import SwiftUI

struct PermissionsSettingsView: View {
    let requestPermission: () -> Void
    let openAppManagementSettings: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("권한 설정") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("접근성 권한 설정", action: requestPermission)
                        Text("창 전환과 앱 메뉴 실행·수집에 사용합니다.").font(.caption).foregroundStyle(.secondary)
                        Button("앱 관리 설정 보기", action: openAppManagementSettings)
                        Text("다른 앱을 업데이트·삭제할 수 있는 권한입니다. Tile Launcher에는 해당 기능이 없습니다. 앱 실행 중 이 권한의 차단 알림이 나타날 때 상태를 확인하는 용도로 제공합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.visible)
    }
}
