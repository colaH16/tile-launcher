import AppKit
import ApplicationServices
import Combine
import DeckCore

/// Observe only the frontmost regular app, covering all apps as the user switches.
/// AX work is serialized off the main thread. No key characters/search text are read.
final class MenuUsageMonitor {
    private let settings: SettingsStore
    private let queue = DispatchQueue(label: "TileLauncher.menu-observation", qos: .utility)
    private var workspaceTokens: [NSObjectProtocol] = []
    private var preferencesToken: AnyCancellable?
    private var inputMonitor: Any?
    private var frontmost: AppItem?
    private var trusted = false
    var onCapture: (() -> Void)?

    // Queue-owned state.
    private var app: AppItem?
    private var lifecycle = MenuObservationLifecycle()
    private var retryWork: DispatchWorkItem?
    private var preferences = MenuCapturePreferences()
    private var observer: AXObserver?
    private var subscriptions: [(AXUIElement, String)] = []
    private var bar: AXUIElement?
    private var openedMenus: [AXUIElement] = []
    private var helpSession = false
    private var menuSession = false
    private var helpCache: [CapturedMenu]?
    private var down: MenuHit?
    private var highlighted: MenuHit?
    private var action: Action?
    private var gate = MenuCaptureGate()
    private var suppressedUntil: TimeInterval = 0
    private var suppressedMenus: Set<MenuIdentity> = []
    private var closedAt: TimeInterval?
    private enum Action { case mouse(CGPoint, TimeInterval), keyboard(TimeInterval) }

    init(settings: SettingsStore) { self.settings = settings }
    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        preferencesToken = settings.$menuCapture.dropFirst().sink { [weak self] value in self?.refresh(preferences: value) }
        refresh()
    }
    func refresh(preferences newPreferences: MenuCapturePreferences? = nil) {
        let options = newPreferences ?? settings.menuCapture
        trusted = AXIsProcessTrusted()
        let running = NSWorkspace.shared.frontmostApplication
        let target: AppItem?
        if let running, running.processIdentifier != getpid(), running.activationPolicy == .regular,
           !running.isTerminated {
            target = AppItem(id: running.bundleIdentifier ?? running.bundleURL?.path ?? String(running.processIdentifier),
                             pid: running.processIdentifier, name: running.localizedName ?? "앱", url: running.bundleURL)
        } else { target = nil }
        frontmost = target
        if options.enabled && trusted {
            if inputMonitor == nil {
                inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] in
                    self?.receiveInput($0)
                }
            }
        } else if let inputMonitor { NSEvent.removeMonitor(inputMonitor); self.inputMonitor = nil }
        let canObserve = trusted && target.map { options.allows(appID: $0.id) } == true
        let process = canObserve ? target.flatMap { ProcessIdentity.read(pid: $0.pid) } : nil
        queue.async { [weak self] in
            self?.configure(process == nil ? nil : target, process: process, preferences: options)
        }
    }
    func stop() {
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens = []
        preferencesToken = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        frontmost = nil
        queue.async { [weak self] in self?.tearDown() }
    }
    func suppressLauncherAction(_ menu: MenuCommand) {
        queue.async { [weak self] in
            self?.suppressedUntil = ProcessInfo.processInfo.systemUptime + 2
            self?.suppressedMenus = Set(MenuPathMatch.paths(menu).map { MenuIdentity(appID: menu.appID, path: $0) })
            self?.resetInteraction()
        }
    }
    private func receiveInput(_ event: NSEvent) {
        guard let target = frontmost, settings.menuCapture.allows(appID: target.id) else { return }
        let type = event.type, time = event.timestamp
        let key: UInt16 = type == .keyDown ? event.keyCode : 0
        let modified = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        let repeatKey = type == .keyDown && event.isARepeat
        let point = event.cgEvent?.location
        let inMenuBar = type != .keyDown && point.map { MenuBarRegion.contains($0, bands: Self.menuBarBands()) } == true
        queue.async { [weak self] in
            guard let self, self.app?.pid == target.pid, self.bar != nil,
                  ProcessInfo.processInfo.systemUptime - time < 1 else { return }
            if type == .keyDown {
                let wasMenu = self.menuSession || self.closedAt.map { time <= $0 && $0 - time < 0.3 } == true
                switch MenuCaptureKeyDecision.resolve(keyCode: key, shortcutModifier: modified,
                                                       repeating: repeatKey, menuWasOpen: wasMenu) {
                case .cancel:
                    self.resetInteraction()
                case .confirm:
                    // Only Return/keypad Enter confirms a menu; typing/search terms are never read.
                    let reader = MenuAXReader(app: target, budget: 0.18)
                    let focused = reader.focusedMenuItem()
                    let hit = focused.flatMap { self.hit($0, reader: reader) }
                        ?? self.selectedHit(reader: reader) ?? self.highlighted
                    self.gate.arm(time: time); self.action = .keyboard(time)
                    if let hit { self.commit(hit, time: time) }
                    self.menuSession = false; self.highlighted = nil
                case .clearHighlight:
                    // A navigation/search key invalidates the old highlight until
                    // AX supplies the newly selected item. Never guess from stale focus.
                    self.highlighted = nil
                }
                return
            }
            guard let point else { return }
            // Most clicks are not on a menu. Skip the AX hit test (which the
            // clicked app must answer) unless a menu can be involved.
            guard inMenuBar || self.menuSession || self.down != nil || !self.openedMenus.isEmpty else {
                self.resetInteraction()
                return
            }
            let reader = MenuAXReader(app: target, budget: 0.18)
            let element = reader.element(at: point)
            let role = element.flatMap { reader.value($0, kAXRoleAttribute) as? String }
            let menuRole = role == kAXMenuItemRole || role == kAXMenuBarItemRole || role == kAXMenuRole
            guard menuRole || self.menuSession || self.down != nil else {
                self.resetInteraction()
                return
            }
            let hit = element.flatMap { self.hit($0, reader: reader) }
            if type == .leftMouseDown {
                self.gate.cancel(); self.action = nil
                self.down = hit
                let path = element.flatMap { reader.menuPath($0) }
                if path.map(MenuCapturePolicy.isAppleMenuPath) == true { self.resetInteraction(); return }
                if hit != nil || path != nil {
                    self.menuSession = true
                    self.closedAt = nil
                    if let first = path?.first { self.helpSession = MenuAXReader.isHelp(first) }
                } else {
                    self.resetInteraction()
                }
            } else {
                self.gate.arm(time: time); self.action = .mouse(point, time)
                let candidate = hit ?? self.down ?? self.highlighted
                if let candidate { self.commit(candidate, time: time) }
                self.down = nil
                // Keep a just-opened top-level menu session; clear after choosing a leaf.
                if candidate != nil { self.menuSession = false; self.highlighted = nil }
            }
        }
    }
    private static func menuBarBands() -> [CGRect] {
        MenuBarRegion.bands(screens: NSScreen.screens.map { ($0.frame, $0.frame.maxY - $0.visibleFrame.maxY) })
    }
    private func configure(_ target: AppItem?, process: ProcessIdentity?, preferences: MenuCapturePreferences) {
        self.preferences = preferences
        if app == target, lifecycle.process == process, bar != nil { return }
        tearDown()
        app = target
        let generation = lifecycle.begin(process)
        guard let target, process != nil else { return }
        connect(target, generation: generation)
    }
    private func connect(_ target: AppItem, generation: UInt64) {
        guard lifecycle.accepts(generation), app == target,
              ProcessIdentity.read(pid: target.pid) == lifecycle.process else { return }
        let reader = MenuAXReader(app: target, budget: 0.2)
        let application = AXUIElementCreateApplication(target.pid)
        guard let bar = reader.element(application, kAXMenuBarAttribute) else {
            if let delay = lifecycle.retryDelay(generation: generation) {
                status("메뉴 준비를 기다리는 중 · 잠시 후 다시 연결합니다.", for: target)
                let work = DispatchWorkItem { [weak self] in self?.connect(target, generation: generation) }
                retryWork = work
                queue.asyncAfter(deadline: .now() + delay, execute: work)
            } else {
                status("메뉴 정보를 읽지 못했습니다. 이 앱으로 다시 전환하면 재시도합니다.", for: target)
            }
            return
        }
        retryWork = nil
        self.bar = bar
        lifecycle.connected(generation: generation)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let owner = Unmanaged<MenuUsageMonitor>.fromOpaque(context).takeUnretainedValue()
            let time = ProcessInfo.processInfo.systemUptime
            owner.queue.async { [weak owner] in owner?.notification(notification as String, element: element, time: time) }
        }
        if AXObserverCreate(target.pid, callback, &created) == .success, let created {
            observer = created
            for element in [application, bar] { subscribe(element) }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        status(subscriptions.isEmpty ? "메뉴 클릭 확인으로 수집합니다. 키보드 메뉴 선택은 제한될 수 있어요."
                                     : "메뉴 선택 대기 중 · 앱별로 일부 선택이 누락될 수 있어요.", for: target)
    }
    private func subscribe(_ element: AXUIElement) {
        guard let observer, subscriptions.count < 96 else { return }
        for name in [kAXMenuOpenedNotification, kAXMenuClosedNotification, kAXMenuItemSelectedNotification] {
            guard !subscriptions.contains(where: { $0.1 == name && CFEqual($0.0, element) }) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.025)
            if AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success {
                subscriptions.append((element, name))
            }
        }
    }
    private func notification(_ name: String, element: AXUIElement, time: TimeInterval) {
        guard let app, bar != nil else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.pid else { return }
        let reader = MenuAXReader(app: app, budget: 0.2)
        if name == kAXMenuOpenedNotification {
            guard let path = reader.menuPath(element), !MenuCapturePolicy.isAppleMenuPath(path) else { resetInteraction(); return }
            if highlighted?.menu.identity.path.first != path.first { highlighted = nil }
            menuSession = true
            closedAt = nil
            helpSession = path.first.map(MenuAXReader.isHelp) == true
            if !openedMenus.contains(where: { CFEqual($0, element) }), openedMenus.count < 32 { openedMenus.append(element) }
            subscribe(element)
            helpCache = nil
        } else if name == kAXMenuClosedNotification {
            openedMenus.removeAll { CFEqual($0, element) }
            if let observer, reader.value(element, kAXRoleAttribute) as? String == kAXMenuRole {
                let closedSubscriptions = subscriptions.filter { CFEqual($0.0, element) }
                for (node, event) in closedSubscriptions { AXObserverRemoveNotification(observer, node, event as CFString) }
                subscriptions.removeAll { CFEqual($0.0, element) }
            }
            if openedMenus.isEmpty {
                if menuSession { closedAt = time }
                menuSession = false
            }
        } else if name == kAXMenuItemSelectedNotification {
            guard let hit = hit(element, reader: reader) else { return }
            highlighted = hit
            // Notification alone is never a use: mouse-up/Return must match it.
            commit(hit, time: time)
        }
    }
    private func selectedHit(reader: MenuAXReader) -> MenuHit? {
        for menu in openedMenus.reversed() {
            if let selected = reader.selectedLeaf(menu), let hit = hit(selected, reader: reader) { return hit }
        }
        return nil
    }
    private func hit(_ element: AXUIElement, reader: MenuAXReader) -> MenuHit? {
        guard let app, let bar, var hit = reader.hit(element, allowHelp: helpSession) else { return nil }
        if hit.isHelpResult {
            if helpCache == nil {
                let catalog = MenuAXReader(app: app, budget: 0.35)
                helpCache = catalog.catalog(bar) ?? []
            }
            guard let resolved = MenuCapturePolicy.resolveHelp(title: hit.menu.identity.path.last ?? "", choices: helpCache ?? []) else { return nil }
            hit = MenuHit(menu: resolved, frame: hit.frame, isHelpResult: true)
        }
        return hit
    }
    private func commit(_ hit: MenuHit, time: TimeInterval) {
        if suppressedMenus.contains(hit.menu.identity), time < suppressedUntil { return }
        let matched: Bool
        switch action {
        case .mouse(let point, let when): matched = time - when <= 0.8 && hit.frame?.contains(point) == true
        case .keyboard(let when): matched = time - when <= 0.8
        case nil: matched = false
        }
        guard let menu = gate.take(hit.menu, matchedUserSelection: matched, time: time, preferences: preferences) else { return }
        let target = app
        DispatchQueue.main.async { [weak self] in
            guard let self, MenuCapturePolicy.allows(menu, preferences: self.settings.menuCapture) else { return }
            self.settings.recordCapturedMenu(menu)
            if let target { self.settings.menuCaptureStatus[target.id] = "메뉴 선택을 수집했습니다." }
            self.onCapture?()
        }
    }
    private func status(_ message: String, for app: AppItem) {
        DispatchQueue.main.async { [weak self] in self?.settings.menuCaptureStatus[app.id] = message }
    }
    private func resetInteraction() {
        gate.cancel(); action = nil; down = nil; highlighted = nil
        menuSession = false; helpSession = false; helpCache = nil
        closedAt = nil
    }
    private func tearDown() {
        retryWork?.cancel(); retryWork = nil
        lifecycle.begin(nil)
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            for (element, name) in subscriptions { AXObserverRemoveNotification(observer, element, name as CFString) }
        }
        observer = nil; subscriptions = []; bar = nil; app = nil; openedMenus = []
        resetInteraction()
    }
}

private struct MenuHit {
    let menu: CapturedMenu
    let frame: CGRect?
    let isHelpResult: Bool
}

/// Bounded read-only AX access. Never reads text field values or executes actions.
private final class MenuAXReader {
    let app: AppItem
    private let deadline: TimeInterval
    init(app: AppItem, budget: TimeInterval) { self.app = app; deadline = ProcessInfo.processInfo.systemUptime + budget }
    private var hasTime: Bool { ProcessInfo.processInfo.systemUptime < deadline }
    func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        guard hasTime else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.025)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    func element(_ owner: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = value(owner, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    func element(at point: CGPoint) -> AXUIElement? {
        guard hasTime else { return nil }
        let owner = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(owner, 0.025)
        var result: AXUIElement?
        guard AXUIElementCopyElementAtPosition(owner, Float(point.x), Float(point.y), &result) == .success else { return nil }
        return result
    }
    private func children(_ element: AXUIElement) -> [AXUIElement]? {
        guard hasTime else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.025)
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
        guard hasTime else { return nil }
        // Childless standard menu items can omit AXChildren. Messaging failures
        // are different: never turn a timed-out submenu into a leaf command.
        if result == .attributeUnsupported || result == .noValue { return [] }
        guard result == .success else { return nil }
        if count == 0 { return [] }
        guard count <= 100 else { return nil }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, count, &values) == .success else { return nil }
        return values as? [AXUIElement]
    }
    func menuPath(_ element: AXUIElement) -> [String]? {
        var current: AXUIElement? = element, path: [String] = []
        for _ in 0..<24 {
            guard let node = current, hasTime else { return nil }
            let role = value(node, kAXRoleAttribute) as? String
            if role == kAXMenuBarRole { return path.reversed() }
            // macOS puts the system Apple menu first. Canonicalize by ancestry,
            // so an empty/localized title cannot turn it into an app command.
            if role == kAXMenuBarItemRole, let parent = self.element(node, kAXParentAttribute),
               value(parent, kAXRoleAttribute) as? String == kAXMenuBarRole,
               let first = children(parent)?.first, CFEqual(first, node) {
                return ["Apple"] + path.reversed()
            }
            if role == kAXMenuItemRole || role == kAXMenuBarItemRole,
               let title = value(node, kAXTitleAttribute) as? String, !title.isEmpty { path.append(title) }
            current = self.element(node, kAXParentAttribute)
        }
        return nil
    }
    static func isHelp(_ value: String) -> Bool {
        ["help", "도움말", "aide", "hilfe", "ayuda", "aiuto", "ヘルプ", "帮助", "說明"].contains(MenuCapturePolicy.normalize(value))
    }
    func hit(_ original: AXUIElement, allowHelp: Bool) -> MenuHit? {
        var current = original
        for _ in 0..<4 {
            if value(current, kAXRoleAttribute) as? String == kAXMenuItemRole { break }
            guard let parent = element(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        guard value(current, kAXRoleAttribute) as? String == kAXMenuItemRole,
              value(current, kAXEnabledAttribute) as? Bool == true,
              let descendants = children(current),
              !descendants.contains(where: { value($0, kAXRoleAttribute) as? String == kAXMenuRole }), hasTime else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(current, &pid) == .success, pid == app.pid else { return nil }
        var actions: CFArray?
        guard hasTime, AXUIElementCopyActionNames(current, &actions) == .success,
              (actions as? [String])?.contains(kAXPressAction) == true else { return nil }
        let path: [String]
        if let exact = menuPath(current), exact.count >= 2 { path = exact }
        else if allowHelp, let title = value(current, kAXTitleAttribute) as? String { path = ["Help", title] }
        else { return nil }
        guard !MenuCapturePolicy.isAppleMenuPath(path) else { return nil }
        guard hasTime else { return nil }
        AXUIElementSetMessagingTimeout(current, 0.025)
        let reading = MenuShortcutReading.read(current)
        let shortcut = reading.shortcut?.key ?? ""
        let modifiers = reading.shortcut?.modifiers ?? 0
        var frame: CGRect?
        if let position = value(current, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
           let size = value(current, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() {
            var point = CGPoint.zero, extent = CGSize.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) {
                frame = CGRect(origin: point, size: extent)
            }
        }
        return MenuHit(menu: CapturedMenu(appID: app.id, appName: app.name, path: path, shortcut: shortcut,
                                         commandModifier: modifiers & (1 << 3) == 0, modifiers: modifiers,
                                         shortcutKnown: reading.known),
                       frame: frame, isHelpResult: path.first.map(Self.isHelp) == true)
    }
    func focusedMenuItem() -> AXUIElement? {
        guard let focused = element(AXUIElementCreateApplication(app.pid), kAXFocusedUIElementAttribute),
              value(focused, kAXRoleAttribute) as? String == kAXMenuItemRole else { return nil }
        return focused
    }
    func selectedLeaf(_ menu: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 10, hasTime else { return nil }
        let selected = value(menu, kAXSelectedChildrenAttribute) as? [AXUIElement] ?? []
        let nodes = selected.isEmpty ? (children(menu) ?? []).filter { value($0, kAXSelectedAttribute) as? Bool == true } : selected
        for node in nodes {
            if let nested = selectedLeaf(node, depth: depth + 1) { return nested }
            if value(node, kAXRoleAttribute) as? String == kAXMenuItemRole { return node }
        }
        return nil
    }
    func catalog(_ bar: AXUIElement) -> [CapturedMenu]? {
        var result: [CapturedMenu] = [], count = 0, complete = true
        func visit(_ node: AXUIElement, path: [String], depth: Int) {
            guard hasTime, count < 800, depth < 12 else { complete = false; return }
            count += 1
            let role = value(node, kAXRoleAttribute) as? String ?? ""
            let title = value(node, kAXTitleAttribute) as? String ?? ""
            let named = role == kAXMenuItemRole || role == kAXMenuBarItemRole
            let next = named && !title.isEmpty ? path + [title] : path
            if next.first.map(Self.isHelp) == true || MenuCapturePolicy.isAppleMenuPath(next) { return }
            guard let descendants = children(node) else { complete = false; return }
            if role == kAXMenuItemRole, descendants.isEmpty, next.count >= 2 {
                AXUIElementSetMessagingTimeout(node, 0.025)
                let reading = MenuShortcutReading.read(node)
                let modifiers = reading.shortcut?.modifiers ?? 0
                result.append(CapturedMenu(appID: app.id, appName: app.name, path: next, shortcut: reading.shortcut?.key ?? "",
                                           commandModifier: modifiers & (1 << 3) == 0, modifiers: modifiers,
                                           shortcutKnown: reading.known))
            } else { descendants.forEach { visit($0, path: next, depth: depth + 1) } }
        }
        guard let roots = children(bar) else { return nil }
        // Exclude the whole Apple subtree, including Location and Recent Items.
        for root in roots.dropFirst() { visit(root, path: [], depth: 0) }
        return complete && hasTime ? result : nil
    }
}
