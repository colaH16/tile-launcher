import AppKit
import ApplicationServices
import DeckCore

private struct TrackedWindow {
    var element: AXUIElement?
    var item: WindowItem
}

/// AX and WindowServer reads stay off the main thread. A partial AX list on a
/// different Space is not a closed-window notification.
final class WindowTracker {
    var onChange: (([WindowItem]) -> Void)?
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
    private let windowEvents = [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                                kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]

    func synchronize(apps list: [AppItem], active: pid_t?, trusted: Bool) {
        queue.async {
            self.activePID = active ?? 0
            self.enabled = trusted
            let newApps = Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
            for pid in Set(self.apps.keys).subtracting(newApps.keys) { self.remove(pid) }
            self.apps = newApps
            if !trusted {
                for pid in Array(self.observers.keys) { self.remove(pid) }
                self.windows.removeAll()
                self.publish()
                return
            }
            self.desktops.refresh()
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
            self.activePID = app.pid
            self.apps[app.pid] = app
            guard self.enabled else { return }
            self.desktops.refresh()
            self.observe(app.pid)
            self.refresh(app.pid, focusEvent: true)
            self.publish()
        }
    }
    func focus(id: UUID, completion: @escaping (String?) -> Void) {
        queue.async {
            guard self.enabled, AXIsProcessTrusted(),
                  let target = self.windows.values.joined().first(where: { $0.item.id == id }) else {
                DispatchQueue.main.async { completion("창에 접근할 수 없습니다. 접근성 권한과 창 상태를 확인해 주세요.") }
                return
            }
            self.desktops.refresh()
            if target.item.isApplication {
                DispatchQueue.main.async {
                    guard let app = target.item.runningApplication, !app.isTerminated else {
                        completion("앱이 종료되었습니다."); return
                    }
                    NSApp.yieldActivation(to: app)
                    completion(app.activate(options: []) ? nil : "앱을 활성화하지 못했습니다.")
                }
                return
            }
            if let number = target.item.windowID, self.desktops.valid,
               self.desktops.records[number]?.pid != target.item.pid {
                DispatchQueue.main.async { completion("이 창이 닫혔습니다.") }
                return
            }
            if let element = target.element, self.isInvalid(element) {
                DispatchQueue.main.async { completion("이 창이 닫혔거나 응답하지 않습니다.") }
                return
            }
            let switched = target.item.windowID.map { self.desktops.revealDesktop(for: $0) } ?? false
            // Space transitions are asynchronous. Retry only resolving/raising a
            // selected window, never menu commands or a different app window.
            self.resolveFocus(target, attempt: 0, delay: switched ? 0.18 : 0, completion: completion)
        }
    }
    private func resolveFocus(_ target: TrackedWindow, attempt: Int, delay: TimeInterval,
                              completion: @escaping (String?) -> Void) {
        queue.asyncAfter(deadline: .now() + delay) {
            guard self.enabled, AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion("접근성 권한이 해제되었습니다.") }; return
            }
            self.desktops.refresh()
            if let number = target.item.windowID, self.desktops.valid,
               self.desktops.records[number]?.pid != target.item.pid {
                DispatchQueue.main.async { completion("이 창이 닫혔습니다.") }; return
            }
            self.refresh(target.item.pid, focusEvent: false)
            let match = self.windows[target.item.pid]?.first { $0.item.id == target.item.id }
            if let element = match?.element ?? target.element, !self.isInvalid(element) {
                self.raise(element, item: target.item, completion: completion)
                return
            }
            if attempt < 4 {
                self.resolveFocus(target, attempt: attempt + 1, delay: 0.15, completion: completion)
            } else {
                DispatchQueue.main.async {
                    completion("이 앱이 해당 창의 제어 정보를 제공하지 않았습니다. 해당 데스크탑에서 창을 한 번 연 뒤 다시 선택해 주세요.")
                }
            }
        }
    }
    private func raise(_ element: AXUIElement, item: WindowItem, completion: @escaping (String?) -> Void) {
        if value(element, kAXMinimizedAttribute) as? Bool == true {
            guard AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else {
                DispatchQueue.main.async { completion("이 앱의 최소화된 창을 복원하지 못했습니다.") }; return
            }
        }
        DispatchQueue.main.async {
            guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else {
                completion("앱이 종료되었습니다."); return
            }
            NSApp.yieldActivation(to: app)
            guard app.activate(options: []) else { completion("앱을 활성화하지 못했습니다."); return }
            self.queue.async {
                let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                DispatchQueue.main.async { completion(raised == .success ? nil : "앱은 열었지만 이 창을 앞으로 가져오지 못했습니다.") }
            }
        }
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
                self.desktops.refresh()
                self.refresh(pid, focusEvent: pid == self.activePID)
                self.publish()
                return
            }
            self.pending[pid]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending[pid] = nil
                self.desktops.refresh()
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
        let old = windows[pid] ?? []
        var next: [TrackedWindow] = []
        if desktops.valid {
            destroyed[pid] = destroyed[pid, default: []].filter { desktops.records[$0]?.pid == pid }
        }
        for element in elements {
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role = value(element, kAXRoleAttribute) as? String
            let subrole = value(element, kAXSubroleAttribute) as? String
            guard role == kAXWindowRole,
                  subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            let number = desktops.id(for: element, pid: pid)
            let prior = old.first { entry in
                (number != nil && entry.item.windowID == number) || (entry.element.map { CFEqual($0, element) } ?? false)
            }
            let id = prior?.item.id ?? UUID()
            if next.contains(where: { $0.item.id == id }) { continue }
            if let number { destroyed[pid]?.remove(number) }
            let title = (value(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "제목 없는 창"
            let item = WindowItem(id: id, pid: pid, appName: appInfo.name, appURL: appInfo.url,
                                  title: title, minimized: value(element, kAXMinimizedAttribute) as? Bool ?? false,
                                  windowID: number ?? prior?.item.windowID,
                                  desktop: desktops.desktop(for: number ?? prior?.item.windowID))
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
            let minimized = missing.element.flatMap { value($0, kAXMinimizedAttribute) as? Bool } ?? missing.item.minimized
            let retainedAX = missing.element != nil && WindowPresence.retainMissingAX(
                orderedIn: record?.orderedIn, axComplete: axComplete,
                minimized: minimized,
                applicationHidden: NSRunningApplication(processIdentifier: pid)?.isHidden == true)
            let exists = desktops.valid ? number.map {
                desktops.records[$0]?.pid == pid && (retainedAX || desktops.records[$0]?.isCandidate == true)
            } : nil
            guard WindowRetention.keepMissing(serverStillContains: exists,
                                               axInvalid: missing.element.map(isInvalid) ?? false,
                                               destroyed: number.map { destroyed[pid, default: []].contains($0) } ?? false) else {
                if let element = missing.element, let observer = observers[pid] {
                    for key in windowEvents { _ = AXObserverRemoveNotification(observer, element, key as CFString) }
                }
                continue
            }
            missing.item.desktop = desktops.desktop(for: number)
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
                windowID: server.id, desktop: .other)))
        }
        let serverCandidates = desktops.records.values.filter { $0.pid == pid && $0.isCandidate }.count
        if WindowPresence.applicationOnly(axComplete: axComplete, inventoryComplete: desktops.valid,
                                          accessibleWindows: next.count, serverCandidates: serverCandidates) {
            let id = applicationIDs[pid] ?? UUID()
            applicationIDs[pid] = id
            next.append(TrackedWindow(element: nil, item: WindowItem(
                id: id, pid: pid, appName: appInfo.name, appURL: appInfo.url,
                title: "", minimized: false, isApplication: true,
                runningApplication: NSRunningApplication(processIdentifier: pid))))
        }
        windows[pid] = next
        if focusEvent, let focused = value(app, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
           let match = next.first(where: { $0.element.map { CFEqual($0, focused) } ?? false }) {
            recency.touch(match.item.id)
        } else if focusEvent, let application = next.first(where: { $0.item.isApplication }) {
            recency.touch(application.item.id)
        }
    }
    private func remove(_ pid: pid_t) {
        pending.removeValue(forKey: pid)?.cancel()
        windows[pid] = nil
        destroyed[pid] = nil
        applicationIDs[pid] = nil
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
    private func publish() {
        let all = windows.keys.sorted().flatMap { windows[$0, default: []].map(\.item) }
        let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        recency.retain(Set(index.keys))
        let result = recency.sorted(all.map(\.id)).compactMap { index[$0] }
        DispatchQueue.main.async { [weak self] in self?.onChange?(result) }
    }
}
