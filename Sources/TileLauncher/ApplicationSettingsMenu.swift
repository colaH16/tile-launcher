import AppKit
import ApplicationServices
import DeckCore

/// One common action for every app. Nothing is registered in the user's saved
/// menu list: only the current app's standard app-menu items are inspected.
final class ApplicationSettingsMenu {
    private let queue = DispatchQueue(label: "TileLauncher.app-settings", qos: .userInitiated)
    private var requested: AppItem?
    private var reading = false
    private var checked: AppItem?
    private var checkedAt: TimeInterval = 0
    private var available = false
    var onChange: (() -> Void)?

    func hasSettings(in app: AppItem?) -> Bool { app != nil && app == checked && available }

    func refresh(app: AppItem?) {
        requested = app
        guard let app, AXIsProcessTrusted() else {
            checked = nil; available = false; onChange?(); return
        }
        // Share preparation/show and rapid repeats; this is an in-memory cache,
        // not app-specific menu registration or an all-running-apps poll.
        guard !reading, app != checked || ProcessInfo.processInfo.systemUptime - checkedAt >= 1 else { return }
        read(app)
    }
    func cancel() { requested = nil }
    private func read(_ app: AppItem) {
        reading = true
        queue.async { [weak self] in
            let found = try? Self.find(in: app)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                guard self.requested == app else {
                    if let latest = self.requested { self.read(latest) }
                    return
                }
                self.checked = app
                self.checkedAt = ProcessInfo.processInfo.systemUptime
                self.available = found != nil
                self.onChange?()
            }
        }
    }

    /// Resolve again at click time. Suppression is installed before AXPress so
    /// using the common tile cannot auto-register an app-specific duplicate.
    func execute(in app: AppItem, prepare: @escaping (MenuCommand, @escaping () -> Void) -> Void,
                 completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let found: Found
            do {
                guard let value = try Self.find(in: app) else {
                    DispatchQueue.main.async {
                        if self.checked == app { self.available = false; self.onChange?() }
                        completion("이 앱에서 설정 메뉴를 찾지 못했습니다.")
                    }
                    return
                }
                found = value
            } catch {
                DispatchQueue.main.async { completion("앱의 설정 메뉴를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.") }
                return
            }
            DispatchQueue.main.async {
                prepare(found.command) {
                    self.queue.async {
                        let result: AXError
                        if NSRunningApplication(processIdentifier: app.pid)?.isTerminated == false {
                            // Read timeout must not constrain the menu action, which
                            // can take longer while a settings window is being created.
                            AXUIElementSetMessagingTimeout(found.element, 0)
                            result = AXUIElementPerformAction(found.element, kAXPressAction as CFString)
                        } else { result = .invalidUIElement }
                        DispatchQueue.main.async {
                            completion(result == .success ? nil : "설정 메뉴 실행 결과를 확인하지 못했습니다. 대상 앱을 확인해 주세요.")
                        }
                    }
                }
            }
        }
    }

    private struct Found { let element: AXUIElement; let command: MenuCommand }
    private enum ReadError: Error { case unavailable }
    private static func find(in app: AppItem) throws -> Found? {
        guard AXIsProcessTrusted(), NSRunningApplication(processIdentifier: app.pid)?.isTerminated == false else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        func value(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ReadError.unavailable }
            AXUIElementSetMessagingTimeout(element, 0.08)
            var result: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, key as CFString, &result)
            guard status == .success || status == .noValue || status == .attributeUnsupported else { throw ReadError.unavailable }
            return status == .success ? result : nil
        }
        func children(_ element: AXUIElement) throws -> [AXUIElement] {
            try value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        let application = AXUIElementCreateApplication(app.pid)
        guard let rawBar = try value(application, kAXMenuBarAttribute), CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { return nil }
        let bar = rawBar as! AXUIElement
        // macOS's first menu is Apple, followed by the application's own menu.
        // Do not search document/project submenus for a coincidental “Settings”.
        guard let root = try children(bar).dropFirst().first,
              let rootTitle = try value(root, kAXTitleAttribute) as? String,
              !MenuCapturePolicy.isAppleMenuPath([rootTitle]) else { return nil }
        var items: [AXUIElement] = []
        for child in try children(root) {
            if try value(child, kAXRoleAttribute) as? String == kAXMenuRole { items += try children(child) }
        }
        guard items.count <= 100 else { return nil }
        var matches: [(AXUIElement, AppSettingsMenuMatch.Candidate)] = []
        for item in items {
            guard try value(item, kAXRoleAttribute) as? String == kAXMenuItemRole,
                  let title = try value(item, kAXTitleAttribute) as? String, !title.isEmpty else { continue }
            let key = try value(item, kAXMenuItemCmdCharAttribute) as? String ?? ""
            var shortcut: MenuShortcut?
            if !key.isEmpty, let modifiers = try value(item, kAXMenuItemCmdModifiersAttribute) as? Int {
                shortcut = MenuShortcut(key: key, modifiers: modifiers)
            }
            guard shortcut == MenuShortcut(key: ",", modifiers: 0) || AppSettingsMenuMatch.isSettingsTitle(title) else { continue }
            // A Settings submenu is not the standard settings-window action.
            guard try children(item).isEmpty else { continue }
            matches.append((item, .init(title: title, shortcut: shortcut)))
        }
        guard let index = AppSettingsMenuMatch.index(in: matches.map(\.1)) else { return nil }
        let (element, candidate) = matches[index]
        guard try value(element, kAXEnabledAttribute) as? Bool == true else { return nil }
        var actions: CFArray?
        guard ProcessInfo.processInfo.systemUptime < deadline,
              AXUIElementCopyActionNames(element, &actions) == .success,
              (actions as? [String] ?? []).contains(kAXPressAction) else { return nil }
        var command = MenuCommand(appID: app.id, appName: app.name, path: [rootTitle, candidate.title])
        command.shortcut = candidate.shortcut
        return Found(element: element, command: command)
    }
}
