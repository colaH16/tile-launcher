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
        }, trusted: { true }, processIdentity: { pid in
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
        starts[a.pid] = 2
        try activate(a)
        try require(reads.count(a.pid) == 2, "PID reuse must reset successful cache")
        service.invalidate(pid: a.pid)
        try activate(a)
        try require(reads.count(a.pid) == 3, "Termination must invalidate the cache")
        service.cancel()

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
        }, trusted: { true }, processIdentity: { pid in
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
        }, trusted: { false })
        untrusted.refresh(app: a)
        try require(!untrusted.hasSettings(in: a), "Untrusted app exposed settings")
        print("App settings cache: activation-only reads, five-failure stop, successful cache, recovery, PID reuse, termination and cancelled results passed.")
    }
}
