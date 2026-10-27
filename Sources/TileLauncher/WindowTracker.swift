import AppKit
import ApplicationServices
import DeckCore

private struct TrackedWindow {
    var element: AXUIElement?
    var item: WindowItem
}

private final class WindowFocusRequest {
    private let lock = NSLock()
    private var cancelled = false
    var active: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}

/// AX and WindowServer reads stay off the main thread. A partial AX list on a
/// different Space is not a closed-window notification.
final class WindowTracker {
    var onChange: (([WindowItem]) -> Void)?
    var onFocusConfirmed: ((WindowItem) -> Void)?
    private let queue = DispatchQueue(label: "TileLauncher.accessibility", qos: .userInitiated)
    private let desktops = DesktopWindows()
    private var apps: [pid_t: AppItem] = [:]
    private var windows: [pid_t: [TrackedWindow]] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var destroyed: [pid_t: Set<CGWindowID>] = [:]
    private var recency = Recency<UUID>()
    private var activePID: pid_t = 0
    private var enabled = false
    private var pending: [pid_t: DispatchWorkItem] = [:]
    private var applicationIDs: [pid_t: UUID] = [:]
    private var focusRequest: WindowFocusRequest?
    private var readRetries: [pid_t: DispatchWorkItem] = [:]
    private var retryBudgets: [pid_t: AXReadRetryBudget] = [:]
    private let windowEvents = [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                                kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                                kAXMovedNotification, kAXResizedNotification]

    func synchronize(apps list: [AppItem], active: pid_t?, trusted: Bool) {
        queue.async {
            self.activePID = active ?? 0
            self.enabled = trusted
            let newApps = Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
            for pid in Set(self.apps.keys).subtracting(newApps.keys) { self.remove(pid) }
            self.apps = newApps
            if !trusted {
                for pid in Array(self.readRetries.keys) { self.cancelReadRetry(pid, reset: true) }
                for pid in Array(self.observers.keys) { self.remove(pid) }
                self.windows.removeAll()
                self.publish()
                return
            }
            self.refreshDesktops()
            let ordered = list.sorted { ($0.pid == active) && ($1.pid != active) }
            for app in ordered {
                self.observe(app.pid)
                self.refresh(app.pid, focusEvent: app.pid == active)
            }
            self.publish()
        }
    }
    func activate(_ app: AppItem) {
        queue.async {
            self.cancelReadRetry(app.pid, reset: true)
            self.activePID = app.pid
            self.apps[app.pid] = app
            guard self.enabled else { return }
            self.refreshDesktops()
            self.observe(app.pid)
            self.refresh(app.pid, focusEvent: true)
            self.publish()
        }
    }
    func focus(id: UUID, completion: @escaping (String?) -> Void) {
        queue.async {
            self.focusRequest?.cancel()
            let request = WindowFocusRequest()
            self.focusRequest = request
            let complete: (String?) -> Void = { message in
                if request.active { completion(message) }
            }
            guard self.enabled, AXIsProcessTrusted(),
                  let target = self.windows.values.joined().first(where: { $0.item.id == id }) else {
                DispatchQueue.main.async { complete("창에 접근할 수 없습니다. 접근성 권한과 창 상태를 확인해 주세요.") }
                return
            }
            self.refreshDesktops()
            if target.item.isApplication {
                DispatchQueue.main.async {
                    guard request.active else { return }
                    guard let app = target.item.runningApplication, !app.isTerminated else {
                        complete("앱이 종료되었습니다."); return
                    }
                    NSApp.yieldActivation(to: app)
                    complete(app.activate(options: []) ? nil : "앱을 활성화하지 못했습니다.")
                }
                return
            }
            if let number = target.item.windowID, self.desktops.valid,
               self.desktops.records[number]?.pid != target.item.pid {
                DispatchQueue.main.async { complete("이 창이 닫혔습니다.") }
                return
            }
            if let element = target.element, self.isInvalid(element) {
                DispatchQueue.main.async { complete("이 창이 닫혔거나 응답하지 않습니다.") }
                return
            }
            // Let AppKit/AX and the Dock coordinate visibility and transitions.
            // WindowServer's direct Space setter can leave both Spaces visible.
            self.resolveFocus(target, request: request, attempt: 0, delay: 0, completion: complete)
        }
    }
    private func resolveFocus(_ target: TrackedWindow, request: WindowFocusRequest, attempt: Int, delay: TimeInterval,
                              completion: @escaping (String?) -> Void) {
        queue.asyncAfter(deadline: .now() + delay) {
            guard request.active else { return }
            guard self.enabled, AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion("접근성 권한이 해제되었습니다.") }; return
            }
            self.refreshDesktops()
            if let number = target.item.windowID, self.desktops.valid,
               self.desktops.records[number]?.pid != target.item.pid {
                DispatchQueue.main.async { completion("이 창이 닫혔습니다.") }; return
            }
            self.refresh(target.item.pid, focusEvent: false)
            let match = self.windows[target.item.pid]?.first { $0.item.id == target.item.id }
            if let element = match?.element ?? target.element, !self.isInvalid(element) {
                self.raise(element, item: target.item, request: request, completion: completion)
                return
            }
            if attempt < 4 {
                if attempt == 0 {
                    // Safari can own the menu bar while its restored window is
                    // still off-Space and absent from AXWindows. Re-activating an
                    // already-active app may not reveal that window. Establish
                    // a real cooperative handoff once, then resolve the same ID.
                    DispatchQueue.main.async {
                        guard request.active else { return }
                        guard let app = NSRunningApplication(processIdentifier: target.item.pid), !app.isTerminated else {
                            completion("앱이 종료되었습니다."); return
                        }
                        if !NSApp.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() { NSApp.activate() }
                        self.handoffForMissingWindow(app, target: target, request: request,
                                                     attempt: 0, completion: completion)
                    }
                } else {
                    self.resolveFocus(target, request: request, attempt: attempt + 1, delay: 0.2, completion: completion)
                }
            } else {
                DispatchQueue.main.async {
                    completion("이 앱이 해당 창의 제어 정보를 제공하지 않았습니다. 해당 데스크탑에서 창을 한 번 연 뒤 다시 선택해 주세요.")
                }
            }
        }
    }
    private func handoffForMissingWindow(_ app: NSRunningApplication, target: TrackedWindow,
                                         request: WindowFocusRequest, attempt: Int,
                                         completion: @escaping (String?) -> Void) {
        // Main-thread run-loop turns allow the source activation to complete.
        // No panel close/pin, synthetic key release, app reopen or Space setter.
        guard request.active else { return }
        guard !app.isTerminated else { completion("앱이 종료되었습니다."); return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let decision = WindowActivationHandoff.evaluate(sourceActive: NSApp.isActive,
            sourceFrontmost: frontmost == getpid(), targetActive: app.isActive, attempt: attempt)
        if decision == .wait {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.handoffForMissingWindow(app, target: target, request: request,
                                             attempt: attempt + 1, completion: completion)
            }
            return
        }
        NSApp.yieldActivation(to: app)
        let accepted = decision == .cooperative
            ? app.activate(from: NSRunningApplication.current, options: [])
            : app.activate(options: [])
        guard accepted else { completion("앱을 활성화하지 못했습니다."); return }
        resolveFocus(target, request: request, attempt: 1, delay: 0.2, completion: completion)
    }
    private func raise(_ element: AXUIElement, item: WindowItem, request: WindowFocusRequest, completion: @escaping (String?) -> Void) {
        guard request.active else { return }
        if value(element, kAXMinimizedAttribute) as? Bool == true {
            guard AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else {
                DispatchQueue.main.async { completion("이 앱의 최소화된 창을 복원하지 못했습니다.") }; return
            }
        }
        // Establish the intended window before app activation so macOS does not
        // choose a different main window/Space for an app with several windows.
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        DispatchQueue.main.async {
            guard request.active else { return }
            guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else {
                completion("앱이 종료되었습니다."); return
            }
            NSApp.yieldActivation(to: app)
            guard app.activate(options: []) else { completion("앱을 활성화하지 못했습니다."); return }
            self.queue.asyncAfter(deadline: .now() + 0.12) {
                guard request.active else { return }
                _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                self.verifyFocus(element, item: item, request: request, attempt: 0, completion: completion)
            }
        }
    }
    private func verifyFocus(_ element: AXUIElement, item: WindowItem, request: WindowFocusRequest, attempt: Int,
                             completion: @escaping (String?) -> Void) {
        guard request.active else { return }
        refreshDesktops()
        let app = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let focused = value(app, kAXFocusedWindowAttribute)
        let matches = focused.map { CFGetTypeID($0) == AXUIElementGetTypeID() && CFEqual($0, element) } ?? false
        let exists = desktops.valid ? item.windowID.map { desktops.records[$0]?.pid == item.pid } : nil
        let status = WindowFocusStatus.evaluate(targetExists: exists,
            frontmost: value(app, kAXFrontmostAttribute) as? Bool == true, focused: matches,
            desktop: desktops.desktop(for: item.windowID), attempt: attempt)
        switch status {
        case .confirmed: DispatchQueue.main.async { [weak self] in
            guard request.active else { return }
            self?.onFocusConfirmed?(item)
            completion(nil)
        }
        case .closed: DispatchQueue.main.async { completion("이 창이 닫혔습니다.") }
        case .unconfirmed:
            DispatchQueue.main.async {
                completion("선택한 창으로 전환됐는지 확인하지 못했습니다. 해당 데스크탑에서 창 상태를 확인해 주세요.")
            }
        case .retry:
            queue.asyncAfter(deadline: .now() + 0.15) {
                self.verifyFocus(element, item: item, request: request, attempt: attempt + 1, completion: completion)
            }
        }
    }
    private func refreshDesktops() {
        desktops.trackedPIDs = Set(apps.keys)
        desktops.knownWindowIDs = Set(windows.values.joined().compactMap(\.item.windowID))
        desktops.refresh()
    }
    private func windowAttributes(_ element: AXUIElement) -> [CFTypeRef?]? {
        WindowAttributeReader.read(element)
    }
    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func isInvalid(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .invalidUIElement
    }
    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let owner = Unmanaged<WindowTracker>.fromOpaque(context).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            owner.schedule(pid, element: element, notification: notification as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        for key in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
            _ = AXObserverAddNotification(observer, app, key as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    private func schedule(_ pid: pid_t, element: AXUIElement, notification: String) {
        queue.async { [self] in
            let pid = pid != 0 ? pid : self.windows.first(where: { entry in
                entry.value.contains { $0.element.map { CFEqual($0, element) } ?? false }
            })?.key ?? 0
            guard self.enabled, self.apps[pid] != nil else { return }
            if notification == kAXUIElementDestroyedNotification {
                let matches = self.windows[pid, default: []].filter { $0.element.map { CFEqual($0, element) } ?? false }
                for match in matches {
                    if let id = match.item.windowID { self.destroyed[pid, default: []].insert(id) }
                }
                self.windows[pid]?.removeAll { window in matches.contains { $0.item.id == window.item.id } }
                self.publish()
            }
            let focused = notification == kAXFocusedWindowChangedNotification
            // Do not coalesce focus events with title/minimize notifications:
            // each focus change contributes to the user's global MRU order.
            if focused {
                self.refreshDesktops()
                self.refresh(pid, focusEvent: pid == self.activePID)
                self.publish()
                return
            }
            self.pending[pid]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending[pid] = nil
                self.refreshDesktops()
                self.refresh(pid, focusEvent: false)
                self.publish()
            }
            self.pending[pid] = work
            self.queue.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
    }
    private func refresh(_ pid: pid_t, focusEvent: Bool) {
        guard enabled, let appInfo = apps[pid] else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var rawWindows: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
        let elements = rawWindows as? [AXUIElement] ?? []
        let axComplete = (readResult == .success && rawWindows is [AXUIElement]) || readResult == .noValue
        // A busy/hung app already used its timeout on the list. Do not spend a
        // further timeout per known window; keep them until the app answers.
        var unresponsive = readResult == .cannotComplete
        defer {
            if unresponsive { scheduleReadRetry(pid, focusEvent: focusEvent) }
            else { cancelReadRetry(pid, reset: true) }
        }
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            guard !unresponsive else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.15)
            var raw: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, key as CFString, &raw)
            if result == .cannotComplete { unresponsive = true }
            return result == .success ? raw : nil
        }
        let applicationHidden = NSRunningApplication(processIdentifier: pid)?.isHidden == true
        let old = windows[pid] ?? []
        var next: [TrackedWindow] = []
        if desktops.valid {
            destroyed[pid] = destroyed[pid, default: []].filter { desktops.records[$0]?.pid == pid }
        }
        for element in elements {
            AXUIElementSetMessagingTimeout(element, 0.15)
            // One timed-out window means the app is busy: stop asking for this
            // refresh and keep the remaining known windows as they were.
            guard let attributes = windowAttributes(element) else { unresponsive = true; break }
            let role = attributes[0] as? String
            let subrole = attributes[1] as? String
            guard role == kAXWindowRole,
                  subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            let frame = Self.bounds(position: attributes[4], size: attributes[5])
            let number = desktops.id(for: element, pid: pid, bounds: frame)
            let prior = old.first { entry in
                (number != nil && entry.item.windowID == number) || (entry.element.map { CFEqual($0, element) } ?? false)
            }
            let id = prior?.item.id ?? UUID()
            if next.contains(where: { $0.item.id == id }) { continue }
            if let number { destroyed[pid]?.remove(number) }
            let title = (attributes[2] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "제목 없는 창"
            let item = WindowItem(id: id, pid: pid, appName: appInfo.name, appURL: appInfo.url,
                                  title: title, minimized: attributes[3] as? Bool ?? false,
                                  windowID: number ?? prior?.item.windowID, appID: appInfo.id,
                                  desktop: desktops.desktop(for: number ?? prior?.item.windowID),
                                  bounds: (number ?? prior?.item.windowID).flatMap { desktops.records[$0]?.bounds }
                                      ?? frame ?? prior?.item.bounds)
            next.append(TrackedWindow(element: element, item: item))
            if prior?.element == nil, let observer = observers[pid] {
                for key in windowEvents {
                    _ = AXObserverAddNotification(observer, element, key as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
            }
        }
        // Preserve off-Space AX handles/titles and MRU IDs until there is positive
        // evidence of closure. A timeout or an incomplete app list is not closure.
        for var missing in old where !missing.item.isApplication && !next.contains(where: { $0.item.id == missing.item.id }) {
            let number = missing.item.windowID
            let record = number.flatMap { desktops.records[$0] }
            let minimized = unresponsive ? missing.item.minimized
                : missing.element.flatMap { read($0, kAXMinimizedAttribute) as? Bool } ?? missing.item.minimized
            var invalid = false
            if !unresponsive, let element = missing.element {
                AXUIElementSetMessagingTimeout(element, 0.15)
                var role: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                invalid = result == .invalidUIElement
                if result == .cannotComplete { unresponsive = true }
            }
            let retainedAX = missing.element != nil && WindowPresence.retainMissingAX(
                orderedIn: record?.orderedIn, axComplete: axComplete && !unresponsive,
                minimized: minimized, applicationHidden: applicationHidden)
            let exists = desktops.valid ? number.map {
                desktops.records[$0]?.pid == pid && (retainedAX || desktops.records[$0]?.isCandidate == true)
            } : nil
            guard WindowRetention.keepMissing(serverStillContains: exists,
                                               axInvalid: invalid,
                                               destroyed: number.map { destroyed[pid, default: []].contains($0) } ?? false) else {
                if let element = missing.element, let observer = observers[pid] {
                    for key in windowEvents { _ = AXObserverRemoveNotification(observer, element, key as CFString) }
                }
                continue
            }
            missing.item.desktop = desktops.desktop(for: number)
            missing.item.bounds = record?.bounds ?? missing.item.bounds
            next.append(missing)
        }
        // A cold start may not have an AX object for a different Space yet. Keep
        // a stable WindowServer identity and resolve AX after explicit selection.
        for server in desktops.records.values.sorted(by: { $0.id < $1.id }) where server.pid == pid {
            guard !next.contains(where: { $0.item.windowID == server.id }),
                  !destroyed[pid, default: []].contains(server.id),
                  server.isCandidate,
                  desktops.desktop(for: server.id) == .other else { continue }
            next.append(TrackedWindow(element: nil, item: WindowItem(
                id: UUID(), pid: pid, appName: appInfo.name, appURL: appInfo.url,
                title: server.title ?? "다른 데스크탑의 창", minimized: false,
                windowID: server.id, appID: appInfo.id, desktop: .other, bounds: server.bounds)))
        }
        let serverCandidates = desktops.records.values.filter { $0.pid == pid && $0.isCandidate }.count
        if unresponsive, next.isEmpty, let prior = old.first(where: { $0.item.isApplication }) {
            next.append(prior)
        }
        if WindowPresence.applicationOnly(axComplete: axComplete && !unresponsive, inventoryComplete: desktops.valid,
                                          accessibleWindows: next.count, serverCandidates: serverCandidates) {
            let id = applicationIDs[pid] ?? UUID()
            applicationIDs[pid] = id
            next.append(TrackedWindow(element: nil, item: WindowItem(
                id: id, pid: pid, appName: appInfo.name, appURL: appInfo.url,
                title: "", minimized: false, appID: appInfo.id, isApplication: true,
                runningApplication: NSRunningApplication(processIdentifier: pid))))
        }
        windows[pid] = next
        if focusEvent, !unresponsive, let focused = read(app, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
           let match = next.first(where: { $0.element.map { CFEqual($0, focused) } ?? false }) {
            recency.touch(match.item.id)
        } else if focusEvent, let application = next.first(where: { $0.item.isApplication }) {
            recency.touch(application.item.id)
        }
    }
    private func cancelReadRetry(_ pid: pid_t, reset: Bool) {
        readRetries.removeValue(forKey: pid)?.cancel()
        if reset { retryBudgets.removeValue(forKey: pid) }
    }
    private func scheduleReadRetry(_ pid: pid_t, focusEvent: Bool) {
        guard enabled, apps[pid] != nil, readRetries[pid] == nil else { return }
        var budget = retryBudgets[pid] ?? AXReadRetryBudget()
        guard let delay = budget.nextDelay() else { return }
        retryBudgets[pid] = budget
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, self.apps[pid] != nil else { return }
            self.readRetries[pid] = nil
            self.refreshDesktops()
            self.refresh(pid, focusEvent: focusEvent && self.activePID == pid)
            self.publish()
        }
        readRetries[pid] = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func remove(_ pid: pid_t) {
        cancelReadRetry(pid, reset: true)
        pending.removeValue(forKey: pid)?.cancel()
        windows[pid] = nil
        destroyed[pid] = nil
        applicationIDs[pid] = nil
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
    private static func bounds(position rawPosition: CFTypeRef?, size rawSize: CFTypeRef?) -> CGRect? {
        guard let rawPosition, let rawSize, CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let position = unsafeBitCast(rawPosition, to: AXValue.self)
        let size = unsafeBitCast(rawSize, to: AXValue.self)
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
    private func publish() {
        let all = windows.keys.sorted().flatMap { windows[$0, default: []].map(\.item) }
        let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        recency.retain(Set(index.keys))
        let result = recency.sorted(all.map(\.id)).compactMap { index[$0] }
        DispatchQueue.main.async { [weak self] in self?.onChange?(result) }
    }
}
