#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import ApplicationServices
import DeckCore

/// Product paths with fake readers only: no AX IPC or user-app activation.
enum AppSettingsProductionValidation {
    private final class Counts {
        private let lock = NSLock()
        private var values: [pid_t: Int] = [:]
        func next(_ pid: pid_t) -> Int { lock.lock(); defer { lock.unlock() }; values[pid, default: 0] += 1; return values[pid]! }
        func count(_ pid: pid_t) -> Int { lock.lock(); defer { lock.unlock() }; return values[pid, default: 0] }
    }
    private final class Race {
        let condition = NSCondition()
        private var entered = 0, ended = 0
        private var released = false
        func start() -> Bool {
            condition.lock(); defer { condition.unlock() }
            entered += 1
            if entered == 3 { released = true; condition.broadcast() }
            let end = Date().addingTimeInterval(1)
            while !released { if !condition.wait(until: end) { return false } }
            return true
        }
        func end() { condition.lock(); ended += 1; condition.unlock() }
        var finished: Int { condition.lock(); defer { condition.unlock() }; return ended }
    }
    @MainActor static func verify() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw NSError(domain: "TileLauncher.SettingsProduction", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait(_ predicate: () -> Bool, timeout: TimeInterval = 3) throws {
            let end = Date().addingTimeInterval(timeout)
            while !predicate(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
            try require(predicate(), "Settings production fixture did not finish")
        }
        let app = AppItem(id: "preview.launched", pid: 123801, name: "Launched", url: nil)
        let other = AppItem(id: "preview.foreground", pid: 123802, name: "Foreground", url: nil)
        func found(_ app: AppItem, suffix: String = "Settings") -> ApplicationSettingsMenu.Found {
            .init(element: AXUIElementCreateApplication(getpid()),
                  command: MenuCommand(appID: app.id, appName: app.name, path: [app.name, suffix]))
        }
        let identity: (pid_t) -> ProcessIdentity? = { .init(pid: $0, startedSeconds: 1, startedMicroseconds: 0) }
        try require(AppSettingsRaceReader.routes == [.multiple, .children, .roleFirst], "Product route selection changed")
        var attributeFailure = AXError.cannotComplete
        let boxedFailure = AXValueCreate(.axError, &attributeFailure)!
        try require(AppSettingsRoute.attributeError(boxedFailure) == .cannotComplete
                    && AppSettingsRoute.attributeError(kCFNull) == nil,
                    "Batch success hid an individual attribute error")
        let race = Race()
        let result = try AppSettingsRaceReader.find(in: app, deadline: ProcessInfo.processInfo.systemUptime + 2,
            cancelled: { false }, reader: { route, _, cancelled in
                guard race.start() else { throw ApplicationSettingsMenu.ReadError.deadline }
                defer { race.end() }
                if route == .children { return found(app, suffix: "Winning Settings") }
                let end = Date().addingTimeInterval(1)
                while !cancelled(), Date() < end { Thread.sleep(forTimeInterval: 0.001) }
                guard cancelled() else { throw NSError(domain: "Loser was not stopped", code: 1) }
                throw ApplicationSettingsMenu.ReadError.cancelled
            })
        try require(result?.command.title == "Winning Settings", "First winner was not returned")
        try wait { race.finished == 3 }
        let recovered = try AppSettingsRaceReader.find(in: app, deadline: ProcessInfo.processInfo.systemUptime + 2,
            cancelled: { false }, reader: { route, _, _ in
                if route == .multiple { throw ApplicationSettingsMenu.ReadError.ax(.cannotComplete) }
                return route == .children ? found(app) : nil
            })
        try require(recovered != nil, "One route's AX error defeated another route's success")
        let absent = try AppSettingsRaceReader.find(in: app, deadline: ProcessInfo.processInfo.systemUptime + 2,
            cancelled: { false }, reader: { _, _, _ in nil })
        try require(absent == nil, "All-miss race fabricated support")

        for incomplete in [false, true] {
            do {
                _ = try AppSettingsRaceReader.find(in: app, deadline: ProcessInfo.processInfo.systemUptime + 2,
                    cancelled: { false }, reader: { route, _, _ in
                        if route == .multiple {
                            if incomplete { throw ApplicationSettingsMenu.ReadError.incomplete }
                            throw ApplicationSettingsMenu.ReadError.ax(.cannotComplete)
                        }
                        return nil
                    })
                try require(false, "Mixed unknown/miss race became confirmed absence")
            } catch is ApplicationSettingsMenu.ReadError { }
        }

        // Display must track the last completed round, independently of retry
        // count. Exercise both foreground and launch-child cache publication.
        for launched in [false, true] {
            let sequence = Counts()
            let stateful = ApplicationSettingsMenu(reader: { item, _, _ in
                let count = sequence.next(item.pid)
                Thread.sleep(forTimeInterval: 0.01)
                if count == 1 { throw ApplicationSettingsMenu.ReadError.ax(.cannotComplete) }
                if count == 2 { return nil }
                if count == 3 { throw ApplicationSettingsMenu.ReadError.incomplete }
                return found(item)
            }, trusted: { true }, retryDelays: [0.02, 0.02, 0.02, 0.02],
               finishedLaunching: { _ in true }, processIdentity: identity)
            var seen: [Int: Bool] = [:]
            stateful.onChange = { seen[sequence.count(app.pid)] = stateful.showsPendingTile(in: app) }
            if launched { stateful.preloadLaunchedApp(app) } else { stateful.refresh(app: app) }
            try wait { stateful.hasSettings(in: app) }
            try require(seen[1] == true && seen[2] == false && seen[3] == true && seen[4] == false,
                        "AX/incomplete errors did not stay disabled, normal miss did not hide, or success did not enable")
            stateful.cancel(); stateful.onChange = nil
        }
        let unknownCalls = Counts()
        let unknown = ApplicationSettingsMenu(reader: { item, _, _ in
            _ = unknownCalls.next(item.pid); throw ApplicationSettingsMenu.ReadError.ax(.cannotComplete)
        }, trusted: { true }, retryDelays: [0.001, 0.001, 0.001, 0.001],
           finishedLaunching: { _ in true }, processIdentity: identity)
        unknown.preloadLaunchedApp(app)
        try wait { unknownCalls.count(app.pid) == 5 && !unknown.isSearching(in: app) }
        try require(unknown.showsPendingTile(in: app) && unknown.pendingTileSearchStopped(in: app),
                    "Exhausted AX errors hid the disabled tile or claimed to still search")
        for _ in 0..<10 { unknown.refresh(app: app); unknown.preloadLaunchedApp(app) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try require(unknownCalls.count(app.pid) == 5, "Unknown result exceeded five attempts")
        unknown.invalidate(pid: app.pid)
        try require(!unknown.showsPendingTile(in: app), "Terminated app kept unknown tile")
        unknown.cancel()

        // Three blocked background IPC calls must not occupy every worker and
        // make a newly activated app wait for their responses.
        let backgroundRoutes = DispatchSemaphore(value: 0), releaseRoutes = DispatchSemaphore(value: 0)
        let backgroundDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            defer { backgroundDone.signal() }
            _ = try? AppSettingsRaceReader.find(in: app, deadline: ProcessInfo.processInfo.systemUptime + 2,
                cancelled: { false }, reader: { _, _, _ in
                    backgroundRoutes.signal(); _ = releaseRoutes.wait(timeout: .now() + 1); return nil
                })
        }
        for _ in 0..<3 {
            try require(backgroundRoutes.wait(timeout: .now() + 1) == .success, "Background routes did not enter")
        }
        let foreground = try AppSettingsRaceReader.find(in: other, deadline: ProcessInfo.processInfo.systemUptime + 0.5,
            cancelled: { false }, reader: { _, _, _ in found(other) })
        for _ in 0..<3 { releaseRoutes.signal() }
        try require(foreground != nil && backgroundDone.wait(timeout: .now() + 1) == .success,
                    "Foreground discovery waited behind blocked background IPC")

        let calls = Counts()
        let prewarm = ApplicationSettingsMenu(reader: { item, _, _ in
            let n = calls.next(item.pid)
            Thread.sleep(forTimeInterval: 0.01)
            return item == app && n < 3 ? nil : found(item)
        }, trusted: { true }, retryDelays: [0.02, 0.02, 0.02, 0.02], finishedLaunching: { _ in true }, processIdentity: identity)
        var sawHiddenRetry = false, sawInitialPending = false
        prewarm.onChange = {
            if prewarm.showsPendingTile(in: app) { sawInitialPending = true }
            if calls.count(app.pid) > 0 && prewarm.isSearching(in: app) && !prewarm.showsPendingTile(in: app) {
                sawHiddenRetry = true
            }
        }
        prewarm.preloadLaunchedApp(app)
        try require(prewarm.showsPendingTile(in: app), "Launch without activation did not show initial pending state")
        for _ in 0..<20 { prewarm.preloadLaunchedApp(app); prewarm.refresh(app: app) }
        prewarm.refresh(app: other) // Must not cancel the launch job.
        try wait { prewarm.hasSettings(in: app) && prewarm.hasSettings(in: other) }
        try require(calls.count(app.pid) == 3 && sawHiddenRetry && sawInitialPending,
                    "Launch retry/dedup/focus independence or pending-hide recovery failed")
        try require(!prewarm.showsPendingTile(in: app), "Confirmed support stayed disabled")
        prewarm.invalidate(pid: app.pid)
        let restarted = AppItem(id: app.id, pid: 123803, name: app.name, url: nil)
        prewarm.preloadLaunchedApp(restarted); prewarm.refresh(app: restarted)
        try require(prewarm.hasSettings(in: restarted) && calls.count(restarted.pid) == 0,
                    "Known capability was re-read after restart")
        prewarm.cancel(); prewarm.onChange = nil

        // Real default completion-relative retry delays, normal nil results.
        let misses = Counts()
        let exhausted = ApplicationSettingsMenu(reader: { item, _, _ in _ = misses.next(item.pid); return nil },
            trusted: { true }, finishedLaunching: { _ in true }, processIdentity: identity)
        exhausted.preloadLaunchedApp(app)
        try wait({ misses.count(app.pid) == 5 && !exhausted.isSearching(in: app) }, timeout: 10)
        try require(!exhausted.showsPendingTile(in: app) && !exhausted.hasSettings(in: app), "Exhausted app still shows a tile")
        for _ in 0..<20 { exhausted.refresh(app: app); exhausted.preloadLaunchedApp(app) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try require(misses.count(app.pid) == 5, "Exhausted process counted/read again")
        exhausted.cancel()

        let deadlines = Counts()
        let budget = ApplicationSettingsMenu(reader: { item, _, _ in
            _ = deadlines.next(item.pid); throw ApplicationSettingsMenu.ReadError.deadline
        }, trusted: { true }, retryDelays: [0.001, 0.001, 0.001, 0.001],
           finishedLaunching: { _ in true }, processIdentity: identity)
        budget.preloadLaunchedApp(app)
        try wait { deadlines.count(app.pid) == 5 && !budget.isSearching(in: app) }
        budget.cancel()

        let block = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let stopped = ApplicationSettingsMenu(reader: { item, _, _ in
            entered.signal(); _ = block.wait(timeout: .now() + 1); return found(item)
        }, trusted: { true }, processIdentity: identity)
        stopped.preloadLaunchedApp(app)
        try require(entered.wait(timeout: .now() + 1) == .success, "Background termination fixture never started")
        stopped.invalidate(pid: app.pid); block.signal()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        try require(!stopped.hasSettings(in: app) && !stopped.isSearching(in: app), "Terminated app published a late result")
        stopped.cancel()

        // A queued app activated by the user bypasses the other background app.
        let backgroundEntered = DispatchSemaphore(value: 0), finishBackground = DispatchSemaphore(value: 0)
        let priority = ApplicationSettingsMenu(reader: { item, _, _ in
            if item == app { backgroundEntered.signal(); _ = finishBackground.wait(timeout: .now() + 2) }
            return found(item)
        }, trusted: { true }, finishedLaunching: { _ in true }, processIdentity: identity)
        priority.preloadLaunchedApp(app)
        try require(backgroundEntered.wait(timeout: .now() + 1) == .success, "Priority fixture never entered")
        priority.preloadLaunchedApp(other); priority.refresh(app: other)
        try wait { priority.hasSettings(in: other) }
        finishBackground.signal()
        try wait { priority.hasSettings(in: app) }
        priority.cancel()

        // Process disappears either before child refresh or after its read.
        for validReads in [2, 3] {
            let identities = Counts()
            let vanished = ApplicationSettingsMenu(reader: { item, _, _ in found(item) }, trusted: { true },
                finishedLaunching: { _ in true }, processIdentity: { pid in
                    if pid == app.pid && identities.next(pid) > validReads { return nil }
                    return identity(pid)
                })
            vanished.preloadLaunchedApp(app)
            try wait { !vanished.isSearching(in: app) }
            try require(!vanished.hasSettings(in: app), "Vanished process published support")
            vanished.preloadLaunchedApp(other)
            try wait { vanished.hasSettings(in: other) }
            vanished.cancel()
        }

        // A lost foreground process must not cancel an unrelated launch read
        // or drop apps queued behind it, even if didTerminate was not delivered.
        let waitingApp = AppItem(id: "preview.queued", pid: 123804, name: "Queued", url: nil)
        let isolatedCalls = Counts()
        let launchEntered = DispatchSemaphore(value: 0), finishLaunch = DispatchSemaphore(value: 0)
        var foregroundAlive = true, foregroundRetryReady = false, foregroundStopNotified = false
        let isolated = ApplicationSettingsMenu(reader: { item, _, _ in
            _ = isolatedCalls.next(item.pid)
            if item == app {
                launchEntered.signal(); _ = finishLaunch.wait(timeout: .now() + 3)
                return found(item)
            }
            if item == other { throw ApplicationSettingsMenu.ReadError.ax(.cannotComplete) }
            return found(item)
        }, trusted: { true }, retryDelays: [0.08], finishedLaunching: { _ in true },
           processIdentity: { pid in pid == other.pid && !foregroundAlive ? nil : identity(pid) })
        defer { finishLaunch.signal(); isolated.cancel(); isolated.onChange = nil }
        isolated.onChange = {
            if !foregroundRetryReady && isolatedCalls.count(other.pid) == 1 && isolated.isSearching(in: other)
                && isolated.showsPendingTile(in: other) {
                foregroundRetryReady = true
                foregroundAlive = false // Completion published; disappear before the retry, without invalidate.
            }
            if foregroundRetryReady && !isolated.isSearching(in: other) { foregroundStopNotified = true }
        }
        isolated.preloadLaunchedApp(app)
        try require(launchEntered.wait(timeout: .now() + 1) == .success, "Isolation fixture did not enter launch read")
        isolated.preloadLaunchedApp(waitingApp)
        isolated.refresh(app: other)
        try wait { foregroundRetryReady }
        try wait { !isolated.isSearching(in: other) }
        try require(foregroundStopNotified && isolated.pendingTileSearchStopped(in: other),
                    "Stopped foreground retry did not publish its disabled failure state")
        try require(isolated.isSearching(in: app) && isolated.isSearching(in: waitingApp),
                    "Foreground retry cancellation discarded unrelated launch work")
        finishLaunch.signal()
        try wait { isolated.hasSettings(in: app) && isolated.hasSettings(in: waitingApp) }
        try require(isolatedCalls.count(other.pid) == 1 && isolatedCalls.count(app.pid) == 1
                    && isolatedCalls.count(waitingApp.pid) == 1,
                    "Cancelled foreground retried or launch work duplicated")
        isolated.cancel(); isolated.onChange = nil

        // A launch child stopping at its retry guard must publish completion
        // so its parent starts the next queued app rather than getting stuck.
        let childCalls = Counts()
        var childAlive = true, childRetryReady = false
        let childStop = ApplicationSettingsMenu(reader: { item, _, _ in
            _ = childCalls.next(item.pid)
            return item == app ? nil : found(item)
        }, trusted: { true }, retryDelays: [0.08], finishedLaunching: { _ in true },
           processIdentity: { pid in pid == app.pid && !childAlive ? nil : identity(pid) })
        childStop.onChange = {
            if !childRetryReady && childCalls.count(app.pid) == 1 && childStop.isSearching(in: app)
                && !childStop.showsPendingTile(in: app) {
                childRetryReady = true; childAlive = false
            }
        }
        defer { childStop.cancel(); childStop.onChange = nil }
        childStop.preloadLaunchedApp(app); childStop.preloadLaunchedApp(waitingApp)
        try wait { childRetryReady }
        try wait { childStop.hasSettings(in: waitingApp) && !childStop.isSearching(in: app) }
        try require(childCalls.count(app.pid) == 1 && childCalls.count(waitingApp.pid) == 1,
                    "Stopped launch child blocked its queue or retried a vanished process")
        childStop.cancel(); childStop.onChange = nil

        // Losing accessibility permission still cancels all app discovery.
        let permissionCalls = Counts()
        let permissionEntered = DispatchSemaphore(value: 0), finishPermissionRead = DispatchSemaphore(value: 0)
        let permissionReaderDone = DispatchSemaphore(value: 0)
        var permissionGranted = true, permissionRetryReady = false
        let permission = ApplicationSettingsMenu(reader: { item, _, _ in
            _ = permissionCalls.next(item.pid)
            if item == app {
                permissionEntered.signal()
                _ = finishPermissionRead.wait(timeout: .now() + 3)
                permissionReaderDone.signal()
                return found(item)
            }
            return nil
        }, trusted: { permissionGranted }, retryDelays: [0.08],
           finishedLaunching: { _ in true }, processIdentity: identity)
        permission.onChange = {
            if !permissionRetryReady && permissionCalls.count(other.pid) == 1 && permission.isSearching(in: other)
                && !permission.showsPendingTile(in: other) {
                permissionRetryReady = true; permissionGranted = false
            }
        }
        defer { finishPermissionRead.signal(); permission.cancel(); permission.onChange = nil }
        permission.preloadLaunchedApp(app)
        try require(permissionEntered.wait(timeout: .now() + 1) == .success, "Permission fixture did not start")
        permission.preloadLaunchedApp(waitingApp); permission.refresh(app: other)
        try wait { permissionRetryReady }
        try wait { !permission.isSearching(in: other) }
        try require(!permission.isSearching(in: app) && !permission.isSearching(in: waitingApp),
                    "Permission loss left unrelated discovery running")
        finishPermissionRead.signal()
        try require(permissionReaderDone.wait(timeout: .now() + 1) == .success, "Permission reader did not finish")
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try require(!permission.hasSettings(in: app) && permissionCalls.count(waitingApp.pid) == 0,
                    "Permission loss published a late result or started queued discovery")
        permission.cancel(); permission.onChange = nil

        let fixture = PreviewFixture(theme: .classic)
        var snapshot = fixture.content.snapshot
        snapshot.hasAppSettings = false; snapshot.appSettingsPending = true
        try require(snapshot.menuEntries().contains { if case .appSettings = $0 { return true }; return false }, "Pending tile missing")
        snapshot.appSettingsPending = false
        try require(!snapshot.menuEntries().contains { if case .appSettings = $0 { return true }; return false }, "Failed round retained pending tile")
        snapshot.hasAppSettings = true
        try require(snapshot.menuEntries().contains { if case .appSettings = $0 { return true }; return false }, "Recovered tile missing")
        print("Product settings: scoped foreground cancellation, stopped-child queue advancement, global permission cancellation, unknown/error vs normal miss, mixed-route errors, stopped disabled tile, three concurrent routes, first winner/loser stop, launch prewarm independent of focus, dedup, hidden retry/reappearance, five normal-miss retries, known restart and termination passed; synthetic only.")
    }
}
#endif
