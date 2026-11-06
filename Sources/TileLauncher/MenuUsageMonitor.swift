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
    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    private let diagnostics = MenuCaptureDiagnostics.makeIfRequested()
    private var diagnosticHelpSession: UInt64 = 0
    private var diagnosticRecentHelpUntil: TimeInterval = 0
    private var diagnosticOrigin: MenuCaptureDiagnostics.Stamp?
    private var diagnosticActionOrigin: MenuCaptureDiagnostics.Stamp?
    private var diagnosticInput: MenuCaptureDiagnostics.Input = .none
    private var diagnosticCatalogComplete: Bool?
    private var diagnosticContext: MenuCaptureDiagnostics.Context {
        .init(generation: lifecycle.generation, helpSession: diagnosticHelpSession)
    }
    private var diagnosticRelevant: Bool {
        diagnostics != nil && (menuSession || helpSession || down != nil || !openedMenus.isEmpty
            || ProcessInfo.processInfo.systemUptime <= diagnosticRecentHelpUntil)
    }
    private func diagnosticNoteHelp(newSession: Bool = false) {
        guard let diagnostics else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if newSession || now > diagnosticRecentHelpUntil { diagnosticHelpSession &+= 1 }
        // Keep a short provenance window after close/reset to explain a queued
        // click rejected before any AX query. Ordinary app clicks are not traced.
        diagnosticRecentHelpUntil = now + 5
        diagnostics.updateContext(diagnosticContext)
    }
    private func diagnosticLog(_ stage: MenuCaptureDiagnostics.Stage, _ outcome: MenuCaptureDiagnostics.Outcome,
                               values original: MenuCaptureDiagnostics.Values = .init(), force: Bool = false) {
        guard let diagnostics, force || diagnosticRelevant else { return }
        var values = original
        if values.input == nil { values.input = diagnosticInput }
        values.menuActive = menuSession
        values.helpActive = helpSession
        let origin = diagnosticOrigin ?? diagnosticActionOrigin
        if let origin {
            values.generationChanged = origin.context.generation != lifecycle.generation
            values.helpSessionChanged = origin.context.helpSession != diagnosticHelpSession
        }
        diagnostics.updateContext(diagnosticContext)
        diagnostics.record(stage, outcome, context: diagnosticContext, origin: origin, values: values)
    }
    private func diagnosticConfigure(_ reader: MenuAXReader) {
        guard diagnostics != nil else { return }
        reader.diagnosticEnabled = true
        reader.diagnosticRow = { [weak self] trace in
            guard let self else { return }
            if trace.helpOwned { self.diagnosticNoteHelp() }
            self.diagnosticLog(.helpRow, trace.failure == .none ? .rowAccepted : .rowRejected,
                               values: .init(cellCount: trace.cellCount, labelCount: trace.labelCount,
                                             rowFailure: trace.failure))
        }
    }
    private static func diagnosticRole(_ role: String?) -> MenuCaptureDiagnostics.Role {
        switch role {
        case nil: return .unknown
        case kAXMenuItemRole: return .menuItem
        case kAXMenuBarItemRole: return .menuBarItem
        case kAXMenuRole: return .menu
        case kAXRowRole: return .row
        case kAXCellRole: return .cell
        case kAXStaticTextRole: return .staticText
        case kAXImageRole: return .image
        default: return .other
        }
    }
    #endif

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
    func suppressLauncherAction(_ menu: MenuCommand, primary: MenuCommand? = nil, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.suppressedUntil = ProcessInfo.processInfo.systemUptime + 2
            self?.suppressedMenus = Set((MenuPathMatch.paths(menu) + (primary.map(MenuPathMatch.paths) ?? [])).map { MenuIdentity(appID: menu.appID, path: $0) })
            self?.resetInteraction()
            if let completion { DispatchQueue.main.async(execute: completion) }
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
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        // Do not log typing/search characters or even a per-character event trail.
        let diagnosticRelevantInput = type != .keyDown || [UInt16(36), 76, 53].contains(key) || modified
        let diagnosticStamp = diagnosticRelevantInput ? diagnostics?.stamp() : nil
        #endif
        queue.async { [weak self] in
            guard let self else { return }
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            let previousOrigin = self.diagnosticOrigin, previousInput = self.diagnosticInput
            self.diagnosticOrigin = diagnosticStamp
            self.diagnosticInput = type == .leftMouseDown ? .mouseDown : type == .leftMouseUp ? .mouseUp : .none
            defer { self.diagnosticOrigin = previousOrigin; self.diagnosticInput = previousInput }
            #endif
            guard self.app?.pid == target.pid, self.bar != nil,
                  ProcessInfo.processInfo.systemUptime - time < 1 else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                if diagnosticRelevantInput {
                    let reason: MenuCaptureDiagnostics.Outcome = self.app?.pid != target.pid ? .staleTarget
                        : self.bar == nil ? .noMenuBar : .staleInput
                    self.diagnosticLog(.input, reason, values: .init(ageMilliseconds:
                        MenuCaptureDiagnostics.milliseconds(ProcessInfo.processInfo.systemUptime - time)))
                }
                #endif
                return
            }
            if type == .keyDown {
                let wasMenu = self.menuSession || self.closedAt.map { time <= $0 && $0 - time < 0.3 } == true
                switch MenuCaptureKeyDecision.resolve(keyCode: key, shortcutModifier: modified,
                                                       repeating: repeatKey, menuWasOpen: wasMenu) {
                case .cancel:
                    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                    self.diagnosticInput = .cancel
                    self.diagnosticLog(.input, .observed)
                    #endif
                    self.resetInteraction()
                case .confirm:
                    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                    self.diagnosticInput = .confirm
                    self.diagnosticLog(.input, .accepted, values: .init(ageMilliseconds:
                        MenuCaptureDiagnostics.milliseconds(ProcessInfo.processInfo.systemUptime - time)))
                    #endif
                    // Only Return/keypad Enter confirms a menu; typing/search terms are never read.
                    let reader = MenuAXReader(app: target, budget: 0.18)
                    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                    self.diagnosticConfigure(reader)
                    #endif
                    let focused = reader.focusedMenuItem()
                    let hit = focused.flatMap { self.hit($0, reader: reader) }
                        ?? self.selectedHit(reader: reader) ?? self.highlighted
                    self.gate.arm(time: time); self.action = .keyboard(time)
                    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                    self.diagnosticActionOrigin = self.diagnosticOrigin
                    #endif
                    if let hit { self.commit(hit, time: time) }
                    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                    if hit == nil { self.diagnosticLog(.hit, .noCandidate, values: reader.diagnosticValues) }
                    #endif
                    self.menuSession = false; self.highlighted = nil
                case .clearHighlight:
                    // A navigation/search key invalidates the old highlight until
                    // AX supplies the newly selected item. Never guess from stale focus.
                    self.highlighted = nil
                }
                return
            }
            guard let point else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                self.diagnosticLog(.input, .noPoint)
                #endif
                return
            }
            // Most clicks are not on a menu. Skip the AX hit test (which the
            // clicked app must answer) unless a menu can be involved.
            guard inMenuBar || self.menuSession || self.down != nil || !self.openedMenus.isEmpty else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                self.diagnosticLog(.input, .unrelated, values: .init(ageMilliseconds:
                    MenuCaptureDiagnostics.milliseconds(ProcessInfo.processInfo.systemUptime - time)))
                #endif
                self.resetInteraction()
                return
            }
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            self.diagnosticLog(.input, .accepted, values: .init(ageMilliseconds:
                MenuCaptureDiagnostics.milliseconds(ProcessInfo.processInfo.systemUptime - time)))
            #endif
            let reader = MenuAXReader(app: target, budget: 0.18)
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            self.diagnosticConfigure(reader)
            #endif
            let element = reader.element(at: point)
            let role = element.flatMap { reader.value($0, kAXRoleAttribute) as? String }
            let menuRole = role == kAXMenuItemRole || role == kAXMenuBarItemRole || role == kAXMenuRole
            let hit = element.flatMap { self.hit($0, reader: reader) }
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            var readValues = reader.diagnosticValues
            readValues.role = Self.diagnosticRole(role)
            readValues.freshHit = hit != nil
            self.diagnosticLog(.hit, hit == nil ? .absent : .observed, values: readValues)
            #endif
            guard menuRole || hit?.isHelpResult == true || self.menuSession || self.down != nil else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                self.diagnosticLog(.hit, .unsupportedHit)
                #endif
                self.resetInteraction()
                return
            }
            if type == .leftMouseDown {
                self.gate.cancel(); self.action = nil
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                self.diagnosticActionOrigin = nil
                #endif
                self.down = hit
                let path = element.flatMap { reader.menuPath($0) }
                if path.map(MenuCapturePolicy.isAppleMenuPath) == true { self.resetInteraction(); return }
                if hit != nil || path != nil {
                    self.menuSession = true
                    self.closedAt = nil
                    if let first = path?.first { self.helpSession = MenuAXReader.isHelp(first) }
                    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                    if self.helpSession { self.diagnosticNoteHelp() }
                    self.diagnosticLog(.menuState, .opened)
                    #endif
                } else {
                    self.resetInteraction()
                }
            } else {
                self.gate.arm(time: time); self.action = .mouse(point, time)
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                self.diagnosticActionOrigin = self.diagnosticOrigin
                #endif
                let candidate = hit ?? self.down ?? self.highlighted
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                self.diagnosticLog(.hit, candidate == nil ? .noCandidate : .observed,
                                   values: .init(hadDown: self.down != nil, hadHighlight: self.highlighted != nil,
                                                 freshHit: hit != nil))
                #endif
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
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        diagnostics?.updateContext(diagnosticContext)
        #endif
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
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        diagnosticConfigure(reader)
        #endif
        if name == kAXMenuOpenedNotification {
            guard let path = reader.menuPath(element), !MenuCapturePolicy.isAppleMenuPath(path) else { resetInteraction(); return }
            if highlighted?.menu.identity.path.first != path.first { highlighted = nil }
            menuSession = true
            closedAt = nil
            helpSession = path.first.map(MenuAXReader.isHelp) == true
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            if helpSession { diagnosticNoteHelp(newSession: path.count == 1) }
            diagnosticLog(.menuState, .opened)
            #endif
            if !openedMenus.contains(where: { CFEqual($0, element) }), openedMenus.count < 32 { openedMenus.append(element) }
            subscribe(element)
            helpCache = nil
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticCatalogComplete = nil
            #endif
            discoverOptions(element, app: app)
            // Some apps emit AXMenuOpened just before the primary links update.
            let process = lifecycle.process
            queue.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                guard let self, self.lifecycle.process == process, self.app == app, self.openedMenus.contains(where: { CFEqual($0, element) }) else { return }
                self.discoverOptions(element, app: app)
            }
        } else if name == kAXMenuClosedNotification {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticLog(.menuState, .closed)
            #endif
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
    private func discoverOptions(_ element: AXUIElement, app: AppItem) {
        let pairs = MenuOptionDiscovery.read(opened: element, app: app)
        MenuOptionDiscovery.shared.remember(pairs, app: app)
        guard !pairs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settings.attachOptionPairs(pairs)
            self.onCapture?()
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
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticNoteHelp()
            #endif
            if helpCache == nil {
                let catalog = MenuAXReader(app: app, budget: 0.35)
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                diagnosticConfigure(catalog)
                let entries = catalog.catalog(bar)
                helpCache = entries ?? []
                diagnosticCatalogComplete = entries != nil
                var values = catalog.diagnosticValues
                values.count = helpCache?.count
                values.cachePresent = false
                values.catalogComplete = entries != nil
                diagnosticLog(.catalog, entries == nil ? .incomplete : .complete, values: values)
                #else
                helpCache = catalog.catalog(bar) ?? []
                #endif
            } else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                diagnosticLog(.catalog, .cacheHit, values: .init(count: helpCache?.count,
                                                               cachePresent: true,
                                                               catalogComplete: diagnosticCatalogComplete))
                #endif
            }
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            var values = MenuCaptureDiagnostics.Values()
            let resolved = MenuCapturePolicy.resolveHelp(title: hit.menu.identity.path.last ?? "", choices: helpCache ?? [],
                                                          diagnostic: diagnostics == nil ? nil : { trace in
                values.candidateCount = trace.candidateCount
                values.identityCount = trace.identityCount
                values.identifierCount = trace.identifierCount
            })
            diagnosticLog(.resolution, resolved == nil ? .unresolved : .resolved, values: values)
            guard let resolved else { return nil }
            #else
            guard let resolved = MenuCapturePolicy.resolveHelp(title: hit.menu.identity.path.last ?? "", choices: helpCache ?? []) else { return nil }
            #endif
            hit = MenuHit(menu: resolved, frame: hit.frame, isHelpResult: true)
        }
        let normalized = MenuOptionDiscovery.shared.normalized(hit.menu, app: app)
        return MenuHit(menu: normalized, frame: hit.frame, isHelpResult: hit.isHelpResult)
    }
    private func commit(_ hit: MenuHit, time: TimeInterval) {
        if suppressedMenus.contains(hit.menu.identity), time < suppressedUntil {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticLog(.gate, .suppressed)
            #endif
            return
        }
        let matched: Bool
        switch action {
        case .mouse(let point, let when): matched = time - when <= 0.8 && hit.frame?.contains(point) == true
        case .keyboard(let when): matched = time - when <= 0.8
        case nil: matched = false
        }
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        var matchValues = MenuCaptureDiagnostics.Values()
        if case .some(.mouse(let point, let when)) = action {
            // Use only the point/frame already used above. Neither is logged.
            matchValues.frameContains = hit.frame?.contains(point) == true
            matchValues.ageMilliseconds = MenuCaptureDiagnostics.milliseconds(time - when)
        }
        var decision: MenuCaptureGate.DiagnosticOutcome?
        let taken = gate.take(hit.menu, matchedUserSelection: matched, time: time, preferences: preferences,
                              diagnostic: diagnostics == nil ? nil : { decision = $0 })
        let outcome: MenuCaptureDiagnostics.Outcome
        switch decision {
        case .some(.accepted): outcome = .accepted
        case .some(.unarmed): outcome = .unarmed
        case .some(.consumed): outcome = .consumed
        case .some(.beforeArm): outcome = .beforeArm
        case .some(.expired): outcome = .expired
        case .some(.unmatched): outcome = .unmatched
        case .some(.policyRejected): outcome = .policyRejected
        case nil: outcome = .absent
        }
        let passiveHighlight: Bool
        switch (action, decision) {
        case (nil, .some(.unarmed)): passiveHighlight = true
        default: passiveHighlight = false
        }
        // AX highlighting alone is not a selection. Keep the limited log for
        // physical actions, including an unexpected unarmed action failure.
        if !passiveHighlight { diagnosticLog(.gate, outcome, values: matchValues) }
        guard let menu = taken else { return }
        let diagnosticRecordContext = diagnosticRelevant ? diagnosticContext : nil
        let diagnosticRecordOrigin = diagnosticOrigin ?? diagnosticActionOrigin
        diagnosticLog(.record, .queued)
        #else
        guard let menu = gate.take(hit.menu, matchedUserSelection: matched, time: time, preferences: preferences) else { return }
        #endif
        let target = app
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard MenuCapturePolicy.allows(menu, preferences: self.settings.menuCapture) else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                if let diagnosticRecordContext {
                    self.diagnostics?.record(.record, .settingsRejected, context: diagnosticRecordContext, origin: diagnosticRecordOrigin)
                }
                #endif
                return
            }
            self.settings.recordCapturedMenu(menu)
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            if let diagnosticRecordContext {
                self.diagnostics?.record(.record, .recorded, context: diagnosticRecordContext, origin: diagnosticRecordOrigin)
            }
            #endif
            if let target { self.settings.menuCaptureStatus[target.id] = "메뉴 선택을 수집했습니다." }
            self.onCapture?()
        }
    }
    private func status(_ message: String, for app: AppItem) {
        DispatchQueue.main.async { [weak self] in self?.settings.menuCaptureStatus[app.id] = message }
    }
    private func resetInteraction() {
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        diagnosticLog(.menuState, .reset)
        diagnosticActionOrigin = nil
        diagnosticCatalogComplete = nil
        #endif
        gate.cancel(); action = nil; down = nil; highlighted = nil
        menuSession = false; helpSession = false; helpCache = nil
        closedAt = nil
    }
    private func tearDown() {
        retryWork?.cancel(); retryWork = nil
        lifecycle.begin(nil)
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        diagnostics?.updateContext(diagnosticContext)
        #endif
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
    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    var diagnosticEnabled = false
    var diagnosticRow: ((MenuHelpSearchRow.Diagnostic) -> Void)?
    private let diagnosticStarted: TimeInterval
    private var diagnosticStats = MenuCaptureDiagnostics.Values()
    var diagnosticValues: MenuCaptureDiagnostics.Values {
        var result = diagnosticStats
        if diagnosticEnabled {
            result.durationMilliseconds = MenuCaptureDiagnostics.milliseconds(ProcessInfo.processInfo.systemUptime - diagnosticStarted)
        }
        return result
    }
    private func diagnosticReadError(_ error: AXError) {
        guard diagnosticEnabled, error != .success else { return }
        if error == .attributeUnsupported || error == .noValue {
            diagnosticStats.missingValues = (diagnosticStats.missingValues ?? 0) + 1
        } else {
            diagnosticStats.ipcFailures = (diagnosticStats.ipcFailures ?? 0) + 1
        }
    }
    #endif
    init(app: AppItem, budget: TimeInterval) {
        self.app = app
        let start = ProcessInfo.processInfo.systemUptime
        deadline = start + budget
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        diagnosticStarted = start
        #endif
    }
    private var hasTime: Bool {
        let available = ProcessInfo.processInfo.systemUptime < deadline
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        if diagnosticEnabled && !available { diagnosticStats.budgetExceeded = true }
        #endif
        return available
    }
    func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        guard hasTime else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.025)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &result)
        guard error == .success else {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticReadError(error)
            #endif
            return nil
        }
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
        let error = AXUIElementCopyElementAtPosition(owner, Float(point.x), Float(point.y), &result)
        guard error == .success else {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticReadError(error)
            #endif
            return nil
        }
        return result
    }
    private func children(_ element: AXUIElement) -> [AXUIElement]? {
        guard hasTime else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.025)
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
        guard hasTime else { return nil }
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        if diagnosticEnabled {
            diagnosticReadError(result)
            diagnosticStats.childCount = max(diagnosticStats.childCount ?? 0, count)
        }
        #endif
        // Childless standard menu items can omit AXChildren. Messaging failures
        // are different: never turn a timed-out submenu into a leaf command.
        if result == .attributeUnsupported || result == .noValue { return [] }
        guard result == .success else { return nil }
        if count == 0 { return [] }
        guard count <= 100 else {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            if diagnosticEnabled { diagnosticStats.childLimit = true }
            #endif
            return nil
        }
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, count, &values)
        guard error == .success else {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticReadError(error)
            #endif
            return nil
        }
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
        MenuCapturePolicy.isHelpMenuTitle(value)
    }
    func hit(_ original: AXUIElement, allowHelp: Bool) -> MenuHit? {
        let role = value(original, kAXRoleAttribute) as? String
        if [kAXRowRole, kAXCellRole, kAXStaticTextRole, kAXImageRole].contains(role ?? ""),
           let result = helpSearchHit(original) { return result }
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
                                         shortcutKnown: reading.known,
                                         axIdentifier: value(current, kAXIdentifierAttribute) as? String),
                       frame: frame, isHelpResult: path.first.map(Self.isHelp) == true)
    }
    private func helpSearchHit(_ original: AXUIElement) -> MenuHit? {
        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(original, &pid)
        guard pidError == .success, pid == app.pid else {
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            diagnosticReadError(pidError)
            #endif
            return nil
        }
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        let result = MenuHelpSearchRow.read(from: original, role: { node in
            switch self.value(node, kAXRoleAttribute) as? String {
            case kAXRowRole: return .row
            case kAXCellRole: return .cell
            case kAXTableRole: return .table
            case kAXStaticTextRole: return .staticText
            default: return .other
            }
        }, parent: { self.element($0, kAXParentAttribute) }, children: children,
           staticText: { self.value($0, kAXValueAttribute) as? String },
           frame: frame, menuPath: menuPath, diagnostic: diagnosticEnabled ? diagnosticRow : nil)
        #else
        let result = MenuHelpSearchRow.read(from: original, role: { node in
            switch self.value(node, kAXRoleAttribute) as? String {
            case kAXRowRole: return .row
            case kAXCellRole: return .cell
            case kAXTableRole: return .table
            case kAXStaticTextRole: return .staticText
            default: return .other
            }
        }, parent: { self.element($0, kAXParentAttribute) }, children: children,
           staticText: { self.value($0, kAXValueAttribute) as? String },
           frame: frame, menuPath: menuPath)
        #endif
        guard let result, hasTime else { return nil }
        return MenuHit(menu: CapturedMenu(appID: app.id, appName: app.name, path: ["Help", result.label]),
                       frame: result.frame, isHelpResult: true)
    }
    private func frame(_ node: AXUIElement) -> CGRect? {
        guard let position = value(node, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(node, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
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
            let timeAvailable = hasTime
            guard timeAvailable, count < 800, depth < 12 else {
                #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
                if diagnosticEnabled {
                    if !timeAvailable { diagnosticStats.budgetExceeded = true }
                    else if count >= 800 { diagnosticStats.nodeLimit = true }
                    else if depth >= 12 { diagnosticStats.depthLimit = true }
                    diagnosticStats.depth = max(diagnosticStats.depth ?? 0, depth)
                }
                #endif
                complete = false
                return
            }
            count += 1
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            if diagnosticEnabled {
                diagnosticStats.nodeCount = count
                diagnosticStats.depth = max(diagnosticStats.depth ?? 0, depth)
            }
            #endif
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
                                           shortcutKnown: reading.known,
                                           axIdentifier: value(node, kAXIdentifierAttribute) as? String))
            } else { descendants.forEach { visit($0, path: next, depth: depth + 1) } }
        }
        guard let roots = children(bar) else { return nil }
        // Exclude the whole Apple subtree, including Location and Recent Items.
        for root in roots.dropFirst() { visit(root, path: [], depth: 0) }
        return complete && hasTime ? result : nil
    }
}
