import AppKit
import ApplicationServices
import DeckCore

private struct TrackedWindow {
    let element: AXUIElement
    var item: WindowItem
}

/// AX calls are confined to this queue and have a per-message timeout.
/// Rendering never waits for another application's accessibility server.
final class WindowTracker {
    var onChange: (([WindowItem]) -> Void)?
    private let queue = DispatchQueue(label: "TileLauncher.accessibility", qos: .userInitiated)
    private var apps: [pid_t: AppItem] = [:]
    private var windows: [pid_t: [TrackedWindow]] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var recency = Recency<UUID>()
    private var activePID: pid_t = 0
    private var enabled = false
    private var pending: [pid_t: DispatchWorkItem] = [:]

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
            // Frontmost context is available first even when a background app is slow.
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
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(target.element, kAXRoleAttribute as CFString, &role) == .success else {
                DispatchQueue.main.async { completion("이 창이 닫혔거나 응답하지 않습니다.") }
                return
            }
            let minimized = self.value(target.element, kAXMinimizedAttribute) as? Bool ?? false
            if minimized {
                let result = AXUIElementSetAttributeValue(target.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                guard result == .success else {
                    DispatchQueue.main.async { completion("이 앱의 최소화된 창을 복원하지 못했습니다.") }
                    return
                }
            }
            DispatchQueue.main.async {
                guard let app = NSRunningApplication(processIdentifier: target.item.pid), !app.isTerminated else {
                    completion("앱이 종료되었습니다.")
                    return
                }
                NSApp.yieldActivation(to: app)
                guard app.activate(options: []) else {
                    completion("앱을 활성화하지 못했습니다.")
                    return
                }
                self.queue.async {
                    let raised = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
                    _ = AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                    DispatchQueue.main.async {
                        completion(raised == .success ? nil : "앱은 열었지만 이 창을 앞으로 가져오지 못했습니다.")
                    }
                }
            }
        }
    }

    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let owner = Unmanaged<WindowTracker>.fromOpaque(context).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let focused = notification as String == kAXFocusedWindowChangedNotification
            owner.schedule(pid, focusEvent: focused)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        for key in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
            _ = AXObserverAddNotification(observer, app, key as CFString, pointer)
        }
        observers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func schedule(_ pid: pid_t, focusEvent: Bool) {
        queue.async {
            guard self.enabled, self.apps[pid] != nil else { return }
            // Focus events retain event order. Title/creation events are coalesced.
            if focusEvent {
                self.refresh(pid, focusEvent: pid == self.activePID)
                self.publish()
                return
            }
            self.pending[pid]?.cancel()
            let work = DispatchWorkItem { [weak tracker = self] in
                guard let self = tracker else { return }
                self.pending[pid] = nil
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
        guard let elements = value(app, kAXWindowsAttribute) as? [AXUIElement] else { return }
        let old = windows[pid] ?? []
        var next: [TrackedWindow] = []
        for element in elements {
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role = value(element, kAXRoleAttribute) as? String
            let subrole = value(element, kAXSubroleAttribute) as? String
            guard role == kAXWindowRole,
                  subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            let id = old.first(where: { CFEqual($0.element, element) })?.item.id ?? UUID()
            let title = (value(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "제목 없는 창"
            let item = WindowItem(id: id, pid: pid, appName: appInfo.name, appURL: appInfo.url,
                                  title: title, minimized: value(element, kAXMinimizedAttribute) as? Bool ?? false)
            next.append(TrackedWindow(element: element, item: item))
            if !old.contains(where: { $0.item.id == id }), let observer = observers[pid] {
                for key in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                    _ = AXObserverAddNotification(observer, element, key as CFString,
                                                   Unmanaged.passUnretained(self).toOpaque())
                }
            }
        }
        if let observer = observers[pid] {
            for removed in old where !next.contains(where: { $0.item.id == removed.item.id }) {
                for key in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                    _ = AXObserverRemoveNotification(observer, removed.element, key as CFString)
                }
            }
        }
        windows[pid] = next
        if focusEvent, let focused = value(app, kAXFocusedWindowAttribute),
           CFGetTypeID(focused) == AXUIElementGetTypeID(),
           let match = next.first(where: { CFEqual($0.element, focused) }) {
            recency.touch(match.item.id)
        }
    }

    private func remove(_ pid: pid_t) {
        pending.removeValue(forKey: pid)?.cancel()
        windows[pid] = nil
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
