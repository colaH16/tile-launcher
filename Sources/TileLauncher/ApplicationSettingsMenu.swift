import AppKit
import ApplicationServices
import DeckCore

/// One common action for every app. Nothing is registered in the user's saved
/// menu list: only each target app's standard app-menu items are inspected.
final class ApplicationSettingsMenu {
    typealias Reader = (AppItem, TimeInterval, () -> Bool) throws -> Found?
    private let queue = DispatchQueue(label: "TileLauncher.app-settings", qos: .userInitiated)
    private let reader: Reader?
    private let trusted: () -> Bool
    private let readTimeout: TimeInterval
    private let processIdentity: (pid_t) -> ProcessIdentity?
    private let finishedLaunching: (pid_t) -> Bool
    private let launchWaitTimeout: TimeInterval
    private let retryDelays: [TimeInterval]
    private let retryMisses: Bool
    private var launchedQueue: [AppItem] = []
    private var launchedReader: ApplicationSettingsMenu?
    private var launchedApp: AppItem?
    private var retryTimer: DispatchWorkItem?
    private enum CacheState { case found, failures(Int), unavailable }
    private struct Cached { let appID: String; let process: ProcessIdentity; let state: CacheState }
    private var cache: [pid_t: Cached] = [:]
    // Capability only: no PID, AX element or menu action survives an app restart.
    // Keep successful app IDs until this launcher instance exits.
    private var supportedAppIDs: Set<String> = []
    private var requested: AppItem?
    private final class LaunchWait {
        let app: AppItem
        let process: ProcessIdentity
        var fallback: DispatchWorkItem?
        init(app: AppItem, process: ProcessIdentity) { self.app = app; self.process = process }
    }
    private var waitingForLaunch: LaunchWait?
    private var request: LookupRequest?
    private var reading = false
    var onChange: (() -> Void)?

    init(reader: Reader? = nil, retryMisses: Bool = true, trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         readTimeout: TimeInterval = 2, launchWaitTimeout: TimeInterval = 1,
         retryDelays: [TimeInterval]? = nil,
         finishedLaunching: @escaping (pid_t) -> Bool = {
             NSRunningApplication(processIdentifier: $0)?.isFinishedLaunching ?? true
         },
         processIdentity: @escaping (pid_t) -> ProcessIdentity? = { ProcessIdentity.read(pid: $0) }) {
        self.reader = reader
        self.trusted = trusted
        self.readTimeout = min(2, max(0, readTimeout))
        self.processIdentity = processIdentity
        self.finishedLaunching = finishedLaunching
        self.launchWaitTimeout = max(0, min(2, launchWaitTimeout))
        self.retryMisses = retryMisses
        self.retryDelays = Array((retryDelays ?? (retryMisses ? [0.4, 0.8, 1.6, 3.2] : [0.4, 0.8])).prefix(4)).map { max(0, $0) }
    }
    private final class LookupRequest {
        let app: AppItem
        let process: ProcessIdentity
        let retryIndex: Int
        private let lock = NSLock()
        private var cancelled = false
        init(app: AppItem, process: ProcessIdentity, retryIndex: Int = 0) {
            self.app = app; self.process = process
            self.retryIndex = retryIndex
        }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    func hasSettings(in app: AppItem?) -> Bool {
        guard let app else { return false }
        return supportedAppIDs.contains(app.id)
    }
    func isSearching(in app: AppItem?) -> Bool {
        guard let app, !hasSettings(in: app) else { return false }
        if requested?.id == app.id, requested?.pid == app.pid, request != nil || waitingForLaunch != nil { return true }
        if launchedApp?.id == app.id, launchedApp?.pid == app.pid { return true }
        return launchedQueue.contains { $0.id == app.id && $0.pid == app.pid }
    }
    /// Only the first unresolved round shows a disabled tile. A failed round
    /// hides it during later retries; a later success creates the active tile.
    func showsPendingTile(in app: AppItem?) -> Bool {
        guard let app, isSearching(in: app) else { return false }
        if let cached = cache[app.pid], cached.appID == app.id {
            switch cached.state { case .failures, .unavailable: return false; case .found: break }
        }
        return true
    }
    /// Launch notifications prewarm the new app independently of the overlay
    /// and current focus. One background app at a time; activation shares it.
    func preloadLaunchedApp(_ app: AppItem) {
        guard trusted(), !hasSettings(in: app), let process = processIdentity(app.pid) else { return }
        if let stored = cache[app.pid], stored.appID == app.id, stored.process == process {
            switch stored.state { case .found, .unavailable: return; case .failures: break }
        } else { cache.removeValue(forKey: app.pid) }
        if requested?.id == app.id, requested?.pid == app.pid {
            if waitingForLaunch != nil { didFinishLaunching(app: app) }
            else if request == nil { refresh(app: app, waitForLaunch: false) }
            onChange?()
            return
        }
        guard !(launchedApp?.id == app.id && launchedApp?.pid == app.pid),
              !launchedQueue.contains(where: { $0.id == app.id && $0.pid == app.pid }) else { return }
        launchedQueue.append(app)
        startNextLaunchedApp()
        onChange?()
    }
    private func startNextLaunchedApp() {
        guard launchedReader == nil, trusted() else { return }
        while !launchedQueue.isEmpty {
            let app = launchedQueue.removeFirst()
            guard !hasSettings(in: app), processIdentity(app.pid) != nil else { continue }
            let child = ApplicationSettingsMenu(reader: reader, retryMisses: retryMisses, trusted: trusted,
                readTimeout: readTimeout, launchWaitTimeout: launchWaitTimeout, retryDelays: retryDelays,
                finishedLaunching: finishedLaunching, processIdentity: processIdentity)
            if let cached = cache[app.pid] { child.cache[app.pid] = cached }
            launchedApp = app; launchedReader = child
            child.onChange = { [weak self, weak child] in
                guard let self, let child, self.launchedReader === child else { return }
                if child.hasSettings(in: app) { self.supportedAppIDs.insert(app.id) }
                if let cached = child.cache[app.pid] { self.cache[app.pid] = cached }
                if !child.isSearching(in: app) {
                    self.launchedReader = nil; self.launchedApp = nil
                    self.startNextLaunchedApp()
                }
                self.onChange?()
            }
            child.refresh(app: app, waitForLaunch: false)
            if launchedReader === child, !child.isSearching(in: app) {
                launchedReader = nil; launchedApp = nil
                continue
            }
            return
        }
    }
    /// Called on activation, startup or an explicit permission/display change.
    /// An activation during launch waits for that process's completion event.
    /// Overlay opening only reads hasSettings and never starts another lookup.
    func refresh(app: AppItem?) {
        refresh(app: app, waitForLaunch: true)
    }
    private func refresh(app: AppItem?, waitForLaunch: Bool) {

        if requested != app {
            clearRetryTimer()
            request?.cancel(); request = nil
            clearLaunchWait()
        }
        requested = app
        guard let app, trusted() else {
            cancel(); cache.removeAll(); onChange?(); return
        }
        if supportedAppIDs.contains(app.id) { return }
        guard let process = processIdentity(app.pid) else {
            invalidate(pid: app.pid); return
        }
        if let work = request, work.process != process {
            clearRetryTimer(); work.cancel(); request = nil
        }
        if let stored = cache[app.pid], stored.appID == app.id, stored.process == process {
            switch stored.state {
            case .found, .unavailable: return
            case .failures: break
            }
        } else { cache.removeValue(forKey: app.pid) }
        if let request, request.app == app, request.process == process {
            return
        }
        // A launch prewarm already in progress owns this process's attempts.
        // Changing focus must not cancel it or start a second set of readers.
        if launchedApp?.id == app.id, launchedApp?.pid == app.pid { return }
        if let index = launchedQueue.firstIndex(where: { $0.id == app.id && $0.pid == app.pid }) {
            // Foreground work must not wait behind another app's readiness retries.
            launchedQueue.remove(at: index)
        }
        if waitForLaunch, !finishedLaunching(app.pid) {
            if waitingForLaunch?.app.id != app.id || waitingForLaunch?.app.pid != app.pid || waitingForLaunch?.process != process {
                clearLaunchWait()
                let waiting = LaunchWait(app: app, process: process)
                waitingForLaunch = waiting
                // Some apps never report finishedLaunching (AppKit SDK contract).
                // One bounded fallback, not a poll or another completed attempt.
                let fallback = DispatchWorkItem { [weak self, weak waiting] in
                    guard let self, let waiting else { return }
                    self.resumeLaunch(waiting)
                }
                waiting.fallback = fallback
                DispatchQueue.main.asyncAfter(deadline: .now() + launchWaitTimeout, execute: fallback)
            }
            return
        }
        clearLaunchWait()
        clearRetryTimer()
        request?.cancel()
        let next = LookupRequest(app: app, process: process)
        request = next
        if !reading { read(next) }
    }
    /// Only resume a deferred activation, never probe an unrelated/background app
    /// or turn every launch notification into another attempt after a failure.
    func didFinishLaunching(app: AppItem) {
        guard let waiting = waitingForLaunch,
              waiting.app.id == app.id, waiting.app.pid == app.pid else { return }
        resumeLaunch(waiting)
    }
    private func resumeLaunch(_ waiting: LaunchWait) {
        guard waitingForLaunch === waiting else { return }
        clearLaunchWait()
        guard requested?.id == waiting.app.id, requested?.pid == waiting.app.pid else { return }
        guard processIdentity(waiting.app.pid) == waiting.process else {
            return
        }

        refresh(app: waiting.app, waitForLaunch: false)
    }
    private func clearLaunchWait() {
        waitingForLaunch?.fallback?.cancel()
        waitingForLaunch = nil
    }
    /// Retire per-process attempts; confirmed app capability stays remembered.
    func invalidate(pid: pid_t) {
        let removed = cache.removeValue(forKey: pid) != nil
        launchedQueue.removeAll { $0.pid == pid }
        if launchedApp?.pid == pid {
            launchedReader?.cancel(); launchedReader = nil; launchedApp = nil
            startNextLaunchedApp()
        }
        if requested?.pid == pid { cancelActive() }
        if removed { onChange?() }
    }
    func cancel() {
        launchedQueue.removeAll()
        launchedReader?.cancel(); launchedReader = nil; launchedApp = nil
        cancelActive()
    }
    private func cancelActive() {
        clearRetryTimer()
        clearLaunchWait()
        requested = nil; request?.cancel(); request = nil
    }
    private func read(_ work: LookupRequest) {
        reading = true
        queue.async { [weak self] in
            guard let self else { return }
            // A round races three routes. Initial misses/AX errors may retry,
            // but completed rounds still share the process's five-failure cap.
            let result: Found?
            var normalMiss = false
            var retryableAXError = false
            var retryableDeadline = false

            if work.isCancelled { result = nil }
            else {
                // Waiting for a cancelled previous app is not part of this app's response budget.
                let deadline = ProcessInfo.processInfo.systemUptime + self.readTimeout
                do {
                    if let reader = self.reader { result = try reader(work.app, deadline, { work.isCancelled }) }
                    else { result = try AppSettingsRaceReader.find(in: work.app, deadline: deadline,
                                                  cancelled: { work.isCancelled }) }
                    normalMiss = result == nil
                } catch let failure as ReadError {
                    result = nil
                    if case .ax = failure { retryableAXError = true }
                    if case .deadline = failure { retryableDeadline = true }
                } catch { result = nil }
            }

            DispatchQueue.main.async {
                self.reading = false
                guard self.request === work, self.requested == work.app, !work.isCancelled else {
                    if let latest = self.request { self.read(latest) }
                    return
                }
                self.request = nil
                guard self.processIdentity(work.app.pid) == work.process else {
                    self.onChange?(); return
                }
                let state: CacheState
                if result != nil {
                    self.supportedAppIDs.insert(work.app.id)
                    state = .found
                }
                else {
                    let failures: Int
                    if let previous = self.cache[work.app.pid], case .failures(let count) = previous.state {
                        failures = count + 1
                    } else { failures = 1 }
                    state = failures >= 5 ? .unavailable : .failures(failures)
                }
                self.cache[work.app.pid] = Cached(appID: work.app.id, process: work.process, state: state)
                let failures: Int
                switch state { case .found: failures = 0; case .failures(let count): failures = count; case .unavailable: failures = 5 }

                let retryable = retryableAXError || (self.retryMisses && (normalMiss || retryableDeadline))
                if retryable && failures < 5 && work.retryIndex < self.retryDelays.count {
                    self.scheduleRetry(after: work)
                }
                self.onChange?()
            }
        }
    }

    private func clearRetryTimer() {
        retryTimer?.cancel(); retryTimer = nil
    }
    private func scheduleRetry(after previous: LookupRequest) {
        let delay = retryDelays[previous.retryIndex]
        let next = LookupRequest(app: previous.app, process: previous.process,
                                 retryIndex: previous.retryIndex + 1)
        request = next
        let timer = DispatchWorkItem { [weak self, weak next] in
            guard let self, let next, self.request === next, self.requested == next.app, !next.isCancelled else { return }
            self.retryTimer = nil
            guard self.trusted() else {
                self.cancel()
                self.cache.removeAll(); self.onChange?(); return
            }
            guard self.processIdentity(next.app.pid) == next.process else {
                self.cancel(); return
            }
            guard !self.supportedAppIDs.contains(next.app.id) else { self.cancel(); return }
            if let stored = self.cache[next.app.pid], case .unavailable = stored.state { self.cancel(); return }

            if !self.reading { self.read(next) }
        }
        retryTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timer)
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
    enum ReadError: Error { case ax(AXError), deadline, cancelled }
    static func find(in app: AppItem,
                             deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 2,
                             isCancelled: () -> Bool = { false },
                             menuBar suppliedBar: AXUIElement? = nil) throws -> Found? {
        guard AXIsProcessTrusted(), NSRunningApplication(processIdentifier: app.pid)?.isTerminated == false else {
            return nil
        }

        func value(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, !isCancelled() else {

                throw remaining <= 0 ? ReadError.deadline : ReadError.cancelled
            }
            AXUIElementSetMessagingTimeout(element, Float(min(0.3, remaining)))

            var result: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, key as CFString, &result)

            guard status == .success || status == .noValue || status == .attributeUnsupported else { throw ReadError.ax(status) }
            return status == .success ? result : nil
        }
        func children(_ element: AXUIElement) throws -> [AXUIElement] {
            try value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        let bar: AXUIElement
        if let suppliedBar { bar = suppliedBar }
        else {
            let application = AXUIElementCreateApplication(app.pid)

            guard let rawBar = try value(application, kAXMenuBarAttribute), CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { return nil }
            bar = rawBar as! AXUIElement
        }
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
        guard let index = AppSettingsMenuMatch.index(in: matches.map(\.1)) else {
            return nil
        }
        let (element, candidate) = matches[index]
        guard try value(element, kAXEnabledAttribute) as? Bool == true else { return nil }
        var actions: CFArray?
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, !isCancelled() else {

            throw remaining <= 0 ? ReadError.deadline : ReadError.cancelled
        }
        AXUIElementSetMessagingTimeout(element, Float(min(0.3, remaining)))

        let actionStatus = AXUIElementCopyActionNames(element, &actions)

        guard actionStatus == .success else { throw ReadError.ax(actionStatus) }
        guard (actions as? [String] ?? []).contains(kAXPressAction) else { return nil }
        var command = MenuCommand(appID: app.id, appName: app.name, path: [rootTitle, candidate.title])
        command.shortcut = candidate.shortcut
        return Found(element: element, command: command)
    }
}
