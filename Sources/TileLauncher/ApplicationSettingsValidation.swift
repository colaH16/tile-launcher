#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import ApplicationServices
import DeckCore

/// Synthetic menu reads only. Never presses a menu or queries another app.
enum ApplicationSettingsValidation {
    private final class Reads {
        private let lock = NSLock()
        private var values: [pid_t: Int] = [:]
        func next(_ pid: pid_t) -> Int {
            lock.lock(); defer { lock.unlock() }
            values[pid, default: 0] += 1
            return values[pid]!
        }
        func count(_ pid: pid_t) -> Int {
            lock.lock(); defer { lock.unlock() }; return values[pid, default: 0]
        }
    }
    @MainActor static func verify() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw NSError(domain: "TileLauncher.SettingsCache", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait(_ condition: () -> Bool) throws {
            let end = Date().addingTimeInterval(2)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            try require(condition(), "Synthetic settings lookup timed out")
        }
        func found(_ app: AppItem) -> ApplicationSettingsMenu.Found {
            .init(element: AXUIElementCreateApplication(getpid()),
                  command: MenuCommand(appID: app.id, appName: app.name, path: [app.name, "Settings…"]))
        }
        let a = AppItem(id: "preview.a", pid: 123001, name: "A", url: nil)
        let b = AppItem(id: "preview.b", pid: 123002, name: "B", url: nil)
        let missing = AppItem(id: "preview.missing", pid: 123003, name: "Missing", url: nil)
        var starts: [pid_t: UInt64] = [:]
        let reads = Reads()
        let service = ApplicationSettingsMenu(reader: { app, _, _ in
            let count = reads.next(app.pid)
            if app == missing { return nil }
            if app == b && count < 3 { return nil }
            return found(app)
        }, retryMisses: false, trusted: { true }, processIdentity: { pid in
            ProcessIdentity(pid: pid, startedSeconds: starts[pid, default: 1], startedMicroseconds: 0)
        })
        var changes = 0
        service.onChange = { changes += 1 }
        func activate(_ app: AppItem) throws {
            let before = changes
            service.refresh(app: app)
            try wait { changes > before }
        }
        try activate(a)
        try require(service.hasSettings(in: a), "Supported app was not cached")
        for _ in 0..<10 { service.refresh(app: a); _ = service.hasSettings(in: a) }
        try require(reads.count(a.pid) == 1 && changes == 1, "Cache hit repeated a lookup or update")
        for _ in 0..<3 { try activate(b); service.refresh(app: a) }
        try require(service.hasSettings(in: b) && reads.count(b.pid) == 3, "Later activation did not recover a failed lookup")
        service.refresh(app: b)
        try require(reads.count(a.pid) == 1 && reads.count(b.pid) == 3, "Switching cached apps queried menus")
        for _ in 0..<5 { try activate(missing); service.refresh(app: a) }
        let exhaustedChanges = changes
        for _ in 0..<20 { service.refresh(app: missing); service.refresh(app: a) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try require(reads.count(missing.pid) == 5 && changes == exhaustedChanges,
                    "Five failed attempts must stop both reads and counter updates")
        starts[missing.pid] = 2
        try activate(missing)
        try require(reads.count(missing.pid) == 6, "PID reuse must reset exhausted cache")
        // A successful capability survives termination, a new PID and even
        // PID reuse by the same app, without a new menu read or change callback.
        starts[a.pid] = 2
        let beforeKnownRestart = changes
        service.refresh(app: a)
        try require(service.hasSettings(in: a) && reads.count(a.pid) == 1 && changes == beforeKnownRestart,
                    "Known app was queried again after restart")
        service.invalidate(pid: a.pid)
        let afterTermination = changes
        let restartedA = AppItem(id: a.id, pid: 123004, name: a.name, url: nil)
        try require(service.hasSettings(in: restartedA), "Known capability disappeared for the new PID")
        service.refresh(app: restartedA)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try require(reads.count(restartedA.pid) == 0 && changes == afterTermination,
                    "Restarted known app repeated a lookup or update")
        let reusedPID = AppItem(id: "preview.unrelated", pid: a.pid, name: "Unrelated", url: nil)
        try require(!service.hasSettings(in: reusedPID), "Capability leaked across app IDs sharing a PID")
        // Disabling/cancelling a query does not erase a known app. UI permission
        // and display settings still gate whether its tile is shown.
        service.cancel()
        try require(service.hasSettings(in: restartedA), "Cancellation erased known capability")
        service.refresh(app: nil)
        try require(service.hasSettings(in: restartedA), "Missing current app erased known capability")
        let freshLauncher = ApplicationSettingsMenu(trusted: { true })
        try require(!freshLauncher.hasSettings(in: restartedA), "Capability persisted into another launcher session")

        // Slow, cancelled requests never publish or spend an attempt; cached
        // activation while another lookup runs must not requeue the old app.
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let serialReads = Reads()
        let serial = ApplicationSettingsMenu(reader: { app, _, cancelled in
            _ = serialReads.next(app.pid)
            if app == b {
                entered.signal()
                _ = release.wait(timeout: .now() + 1)
                if cancelled() { return nil }
            }
            return found(app)
        }, retryMisses: false, trusted: { true }, processIdentity: { pid in
            .init(pid: pid, startedSeconds: 1, startedMicroseconds: 0)
        })
        var serialChanges = 0
        serial.onChange = { serialChanges += 1 }
        serial.refresh(app: a)
        try wait { serial.hasSettings(in: a) }
        serial.refresh(app: b)
        try require(entered.wait(timeout: .now() + 1) == .success, "Slow read never entered")
        serial.refresh(app: a)
        release.signal()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        try require(serialChanges == 1 && !serial.hasSettings(in: b) && serialReads.count(b.pid) == 1,
                    "Cancelled result published or old request was requeued")
        serial.refresh(app: b)
        try require(entered.wait(timeout: .now() + 1) == .success, "Cancelled request could not retry")
        release.signal()
        try wait { serial.hasSettings(in: b) }
        serial.cancel()
        let untrusted = ApplicationSettingsMenu(reader: { _, _, _ in
            throw NSError(domain: "Unexpected untrusted read", code: 1)
        }, retryMisses: false, trusted: { false })
        untrusted.refresh(app: a)
        try require(!untrusted.hasSettings(in: a), "Untrusted app exposed settings")
        print("App settings cache: activation-only reads, app-lifetime success cache, five-failure stop, negative PID reset, launcher reset and cancelled results passed.")
    }
}
#endif
