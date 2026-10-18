import Combine
import DeckCore
import Foundation

/// A window-local edit buffer for each tab. Only the source store drives the
/// overlay, automatic collection and persistent defaults.
final class SettingsEditingSession: ObservableObject {
    let appearance: SettingsStore
    let menus: SettingsStore
    let registered: SettingsStore
    @Published private(set) var errors: [SettingsTab: String] = [:]
    private let source: SettingsStore
    private var appearanceBase: AppearanceSettingsDraft
    private var menuBase: MenuSettingsDraft
    private var registeredBase: RegisteredSettingsDraft
    private var token: AnyCancellable?
    private var draftTokens: [AnyCancellable] = []
    private var syncScheduled = false
    private var observationRevision = 0
    private var menuIcons: MenuIconService?
    var syncStatus: SettingsSyncStatus { source.syncStatus }

    init(source: SettingsStore) {
        self.source = source
        appearance = source.makeEditingCopy()
        menus = source.makeEditingCopy()
        registered = source.makeEditingCopy()
        appearanceBase = Self.appearanceState(source)
        menuBase = Self.menuState(source, usingInputs: false)
        registeredBase = Self.registeredState(source)
        for draft in [appearance, menus, registered] {
            draftTokens.append(draft.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        }
    }
    func activate() {
        synchronize()
        guard token == nil else { return }
        let revision = observationRevision
        token = source.objectWillChange.sink { [weak self] _ in
            guard let self, !self.syncScheduled else { return }
            self.syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observationRevision == revision else { return }
                self.syncScheduled = false
                self.synchronize()
            }
        }
    }
    func pause() {
        token = nil
        observationRevision += 1
        syncScheduled = false
    }
    func activateMenuIcons() {
        guard menuIcons == nil, source.onRefreshMenuIcons != nil else { return }
        menuIcons = MenuIconService(settings: menus, resolveExisting: false, resolveAdded: false)
    }
    func hasChanges(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .general: return false
        case .appearance: return Self.appearanceState(appearance) != appearanceBase
        case .menus:
            return Self.menuState(menus) != menuBase
                || menus.menuRecentDaysInput != String(menuBase.history.recentDays)
                || menus.menuFrequentDaysInput != String(menuBase.history.frequentDays)
                || !menus.refreshingMenuIcons.isEmpty
        case .registered:
            return Self.registeredState(registered) != registeredBase
                || registered.importingDock || registered.dockImportPreview != nil
        }
    }
    func canSave(_ tab: SettingsTab) -> Bool {
        !(syncStatus.locked && (tab == .appearance || tab == .menus)) && hasChanges(tab) && (tab != .menus || (menus.validMenuHistoryInput != nil && menus.refreshingMenuIcons.isEmpty))
            && (tab != .registered || (!registered.importingDock && registered.dockImportPreview == nil))
    }
    func synchronize() {
        let appearanceNow = Self.appearanceState(source)
        apply(Self.appearanceState(appearance).rebased(from: appearanceBase, onto: appearanceNow), to: appearance)
        appearanceBase = appearanceNow
        let menuNow = Self.menuState(source, usingInputs: false)
        let keepRecent = menus.menuRecentDaysInput != String(menuBase.history.recentDays)
        let keepFrequent = menus.menuFrequentDaysInput != String(menuBase.history.frequentDays)
        let nextMenu = Self.menuState(menus).rebased(from: menuBase, onto: menuNow, tombstones: source.syncStatus.deletedMenus)
        apply(nextMenu, to: menus, resetInputs: false)
        if !keepRecent { menus.menuRecentDaysInput = String(nextMenu.history.recentDays) }
        if !keepFrequent { menus.menuFrequentDaysInput = String(nextMenu.history.frequentDays) }
        menuBase = menuNow
        if menus.unavailableMenus != source.unavailableMenus { menus.unavailableMenus = source.unavailableMenus }
        if menus.sharedMenus != source.sharedMenus { menus.sharedMenus = source.sharedMenus }
        if menus.menuCaptureStatus != source.menuCaptureStatus { menus.menuCaptureStatus = source.menuCaptureStatus }
        let registeredNow = Self.registeredState(source)
        do {
            let next = try Self.registeredState(registered).rebased(from: registeredBase, onto: registeredNow)
            apply(next, to: registered)
            registeredBase = registeredNow
            setError(nil, for: .registered)
        } catch {
            setError("등록 목록이 다른 곳에서 바뀌었습니다. 변경 취소로 최신 목록을 불러온 뒤 다시 편집해 주세요.", for: .registered)
        }
        registered.focusProfileID = source.focusProfileID
    }
    func save(_ tab: SettingsTab) {
        synchronize()
        guard canSave(tab) else { return }
        switch tab {
        case .general: return
        case .appearance:
            let state = Self.appearanceState(appearance)
            source.batchSave { apply(state, to: source) }
            appearanceBase = Self.appearanceState(source)
            apply(appearanceBase, to: appearance)
        case .menus:
            var state = Self.menuState(menus)
            let oldIDs = Set(source.commands.map(\.id))
            let retainedIDs = Set(state.commands.map(\.id))
            for removed in source.commands where !retainedIDs.contains(removed.id) {
                let identity = MenuIdentity(appID: removed.appID, path: removed.path)
                if state.capture.excludedMenus.contains(identity) {
                    state.capture.excludedMenus.formUnion(MenuPathMatch.paths(removed).map {
                        MenuIdentity(appID: removed.appID, path: $0)
                    })
                }
            }
            source.batchSave { apply(state, to: source) }
            for command in source.commands where !oldIDs.contains(command.id) { source.onMenuAdded?(command) }
            menuBase = Self.menuState(source, usingInputs: false)
            apply(menuBase, to: menus)
        case .registered:
            do {
                let state = try Self.registeredState(registered).rebased(from: registeredBase, onto: Self.registeredState(source))
                source.batchSave { apply(state, to: source) }
                registeredBase = Self.registeredState(source)
                apply(registeredBase, to: registered)
            } catch {
                setError("등록 목록이 다른 곳에서 바뀌었습니다. 변경 취소로 최신 목록을 불러온 뒤 다시 편집해 주세요.", for: tab)
                return
            }
        }
        if tab == .menus { source.syncStatus.clearIconEdits?() }
        setError(nil, for: tab)
        objectWillChange.send()
    }
    func cancel(_ tab: SettingsTab) {
        switch tab {
        case .general: return
        case .appearance:
            appearanceBase = Self.appearanceState(source)
            apply(appearanceBase, to: appearance)
        case .menus:
            source.syncStatus.clearIconEdits?()
            // Pending resource scans remain tied to the discarded service.
            menuIcons?.invalidatePending()
            menuIcons = nil
            menus.onRefreshMenuIcons = nil
            menus.refreshingMenuIcons = []
            menus.menuIconStatus = [:]
            menuBase = Self.menuState(source, usingInputs: false)
            apply(menuBase, to: menus)
            activateMenuIcons()
        case .registered:
            registered.cancelDockImport()
            registeredBase = Self.registeredState(source)
            apply(registeredBase, to: registered)
        }
        if tab == .menus { source.syncStatus.clearIconEdits?() }
        setError(nil, for: tab)
        objectWillChange.send()
    }
    private func setError(_ value: String?, for tab: SettingsTab) {
        if errors[tab] != value { errors[tab] = value }
    }
    private static func appearanceState(_ store: SettingsStore) -> AppearanceSettingsDraft {
        .init(theme: store.theme, colors: store.tileColors)
    }
    private static func menuState(_ store: SettingsStore, usingInputs: Bool = true) -> MenuSettingsDraft {
        .init(showsAppSettings: store.showAppSettingsTile, capture: store.menuCapture,
              history: usingInputs ? (store.validMenuHistoryInput ?? store.menuHistory) : store.menuHistory,
              commands: store.commands)
    }
    private static func registeredState(_ store: SettingsStore) -> RegisteredSettingsDraft {
        .init(profiles: store.profiles,
              selectedID: store.profiles.contains(where: { $0.id == store.manualProfileID }) ? store.manualProfileID : store.activeProfile.id,
              followsFocus: store.followFocus)
    }
    private func apply(_ value: AppearanceSettingsDraft, to store: SettingsStore) {
        if store.theme != value.theme { store.theme = value.theme }
        if store.tileColors != value.colors { store.tileColors = value.colors }
    }
    private func apply(_ value: MenuSettingsDraft, to store: SettingsStore, resetInputs: Bool = true) {
        if store.commands != value.commands { store.commands = value.commands }
        if store.menuHistory != value.history { store.menuHistory = value.history }
        if store.menuCapture != value.capture { store.menuCapture = value.capture }
        if store.showAppSettingsTile != value.showsAppSettings { store.showAppSettingsTile = value.showsAppSettings }
        if resetInputs {
            store.menuRecentDaysInput = String(value.history.recentDays)
            store.menuFrequentDaysInput = String(value.history.frequentDays)
        }
    }
    private func apply(_ value: RegisteredSettingsDraft, to store: SettingsStore) {
        if store.profiles != value.profiles { store.profiles = value.profiles }
        if store.manualProfileID != value.selectedID { store.manualProfileID = value.selectedID }
        if store.followFocus != value.followsFocus { store.followFocus = value.followsFocus }
    }
}
