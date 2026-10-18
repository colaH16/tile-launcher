import Combine
import DeckCore
import Foundation

/// Shared by the live store and its editor copies; changes are published on main.
final class SettingsSyncStatus: ObservableObject {
    @Published var enabled = false
    @Published var locked = false
    @Published var message = "이 Mac에서 iCloud 동기화를 사용하지 않습니다."
    @Published var error: String?
    @Published var awaitingAccount = false
    @Published var initialConflicts: [String] = []
    @Published var iconConflicts: [SettingsSyncMenu] = []
    var deletedMenus: [UUID: MenuCommand] = [:]
    var setEnabled: ((Bool) -> Void)?
    var refresh: (() -> Void)?
    /// The settings window is visible. Editing locks apply only while it is.
    var setSettingsVisible: ((Bool) -> Void)?
    var chooseInitial: ((Bool) -> Void)?
    var chooseIcon: ((String, String?) -> Void)?
    var beginIconEdit: ((UUID) -> Void)?
    var clearIconEdits: (() -> Void)?
    var checkMenus: ((String) -> Void)?
}
