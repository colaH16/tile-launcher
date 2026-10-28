import AppKit
import ServiceManagement
import SwiftUI

final class LoginItemManager: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var changing = false
    @Published private(set) var error: String?

    var registered: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var statusText: String {
        switch status {
        case .enabled: return "Mac에 로그인하면 메뉴 막대에서 시작합니다."
        case .requiresApproval: return "시스템 설정의 로그인 항목에서 허용해 주세요."
        case .notRegistered: return "로그인할 때 자동으로 실행하지 않습니다."
        case .notFound: return "자동 실행이 아직 등록되지 않았습니다."
        @unknown default: return "시스템 설정에서 로그인 항목을 확인해 주세요."
        }
    }

    func refresh() { status = SMAppService.mainApp.status }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    func setEnabled(_ enabled: Bool) {
        guard !changing else { return }
        error = nil
        refresh()
        guard enabled != registered else { return }
        changing = true
        if enabled {
            do { try SMAppService.mainApp.register() }
            catch { self.error = "자동 실행을 등록하지 못했습니다. \(error.localizedDescription)" }
            changing = false
            refresh()
        } else {
            SMAppService.mainApp.unregister { [weak self] error in
                DispatchQueue.main.async {
                    if let error { self?.error = "자동 실행을 해제하지 못했습니다. \(error.localizedDescription)" }
                    self?.changing = false
                    self?.refresh()
                }
            }
        }
    }
}
