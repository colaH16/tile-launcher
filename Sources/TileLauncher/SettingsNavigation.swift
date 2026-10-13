import Combine
import Foundation

enum SettingsTab: Hashable { case general, appearance, menus, registered, permissions }
enum SettingsDestination { case general, addMenu, registered }

struct MenuAdditionRequest: Identifiable, Equatable {
    let id = UUID()
    let app: AppItem?
}

/// Window-local navigation. A new request also works when settings are already open.
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
    @Published private(set) var preferredApp: AppItem?
    @Published private(set) var menuAddition: MenuAdditionRequest?

    func open(_ destination: SettingsDestination, app: AppItem?) {
        preferredApp = app
        switch destination {
        case .general: tab = .general; menuAddition = nil
        case .registered: tab = .registered; menuAddition = nil
        case .addMenu: tab = .menus; menuAddition = MenuAdditionRequest(app: app)
        }
    }
}
