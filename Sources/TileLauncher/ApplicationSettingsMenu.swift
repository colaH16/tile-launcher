import AppKit
import ApplicationServices
import DeckCore

/// One common action for every app. Nothing is registered in the user's saved
/// menu list: only the current app's standard app-menu items are inspected.
final class ApplicationSettingsMenu {
    typealias Reader = (AppItem, TimeInterval, () -> Bool) throws -> Found?
    private let queue = DispatchQueue(label: "TileLauncher.app-settings", qos: .userInitiated)
    private let reader: Reader
    private let trusted: () -> Bool
    private let readTimeout: TimeInterval
    private let processIdentity: (pid_t) -> ProcessIdentity?
    private enum CacheState { case found, failures(Int), unavailable }
    private struct Cached { let appID: String; let process: ProcessIdentity; let state: CacheState }
    private var cache: [pid_t: Cached] = [:]
    private var requested: AppItem?
    private var request: LookupRequest?
    private var reading = false
    var onChange: (() -> Void)?

    init(reader: Reader? = nil, trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         readTimeout: TimeInterval = 2,
         processIdentity: @escaping (pid_t) -> ProcessIdentity? = { ProcessIdentity.read(pid: $0) }) {
        self.reader = reader ?? { try Self.find(in: $0, deadline: $1, isCancelled: $2) }
        self.trusted = trusted
        self.readTimeout = min(2, max(0, readTimeout))
        self.processIdentity = processIdentity
    }
    private final class LookupRequest {
        let app: AppItem
        let process: ProcessIdentity
        private let lock = NSLock()
        private var cancelled = false
        init(app: AppItem, process: ProcessIdentity) {
            self.app = app; self.process = process
        }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    func hasSettings(in app: AppItem?) -> Bool {
        guard let app else { return false }
        guard let cached = cache[app.pid], cached.appID == app.id else { return false }
        if case .found = cached.state { return true }
        return false
    }
    /// Called on activation, startup or an explicit permission/display change.
    /// Overlay opening only reads hasSettings and never starts another lookup.
    func refresh(app: AppItem?) {
        if requested != app { request?.cancel(); request = nil }
        requested = app
        guard let app, trusted() else {
            cancel(); cache.removeAll(); onChange?(); return
        }
        guard let process = processIdentity(app.pid) else { invalidate(pid: app.pid); return }
        if let stored = cache[app.pid], stored.appID == app.id, stored.process == process {
            switch stored.state {
            case .found, .unavailable: return
            case .failures: break
            }
        } else { cache.removeValue(forKey: app.pid) }
        if let request, request.app == app, request.process == process { return }
        request?.cancel()
        let next = LookupRequest(app: app, process: process)
        request = next
        if !reading { read(next) }
    }
    func invalidate(pid: pid_t) {
        let removed = cache.removeValue(forKey: pid) != nil
        if requested?.pid == pid { cancel() }
        if removed { onChange?() }
    }
    func cancel() { requested = nil; request?.cancel(); request = nil }
    private func read(_ work: LookupRequest) {
        reading = true
        queue.async { [weak self] in
            guard let self else { return }
            // One completed lookup per activation; no timer or retry loop.
            let result: Found?
            if work.isCancelled { result = nil }
            else {
                // Waiting for a cancelled previous app is not part of this app's response budget.
                let deadline = ProcessInfo.processInfo.systemUptime + self.readTimeout
                result = try? self.reader(work.app, deadline, { work.isCancelled })
            }
            DispatchQueue.main.async {
                self.reading = false
                guard self.request === work, self.requested == work.app, !work.isCancelled else {
                    if let latest = self.request { self.read(latest) }
                    return
                }
                self.request = nil
                guard self.processIdentity(work.app.pid) == work.process else { return }
                let state: CacheState
                if result != nil { state = .found }
                else {
                    let failures: Int
                    if let previous = self.cache[work.app.pid], case .failures(let count) = previous.state {
                        failures = count + 1
                    } else { failures = 1 }
                    state = failures >= 5 ? .unavailable : .failures(failures)
                }
                self.cache[work.app.pid] = Cached(appID: work.app.id, process: work.process, state: state)
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
                        self.invalidate(pid: app.pid)
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

    struct Found { let element: AXUIElement; let command: MenuCommand }
    private enum ReadError: Error { case unavailable }
    private static func find(in app: AppItem,
                             deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 2,
                             isCancelled: () -> Bool = { false }) throws -> Found? {
        guard AXIsProcessTrusted(), NSRunningApplication(processIdentifier: app.pid)?.isTerminated == false else { return nil }
        func value(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, !isCancelled() else { throw ReadError.unavailable }
            AXUIElementSetMessagingTimeout(element, Float(min(0.3, remaining)))
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
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, !isCancelled() else { throw ReadError.unavailable }
        AXUIElementSetMessagingTimeout(element, Float(min(0.3, remaining)))
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              (actions as? [String] ?? []).contains(kAXPressAction) else { return nil }
        var command = MenuCommand(appID: app.id, appName: app.name, path: [rootTitle, candidate.title])
        command.shortcut = candidate.shortcut
        return Found(element: element, command: command)
    }
}
