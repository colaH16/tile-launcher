#if TILE_LAUNCHER_DIAGNOSTICS
import AppKit
import ApplicationServices
import DeckCore

/// Launch ordering regression tests with synthetic readers, clocks and PIDs.
enum ApplicationSettingsLaunchValidation {
    private final class Reads {
        private let lock = NSLock()
        private var values: [pid_t: Int] = [:]
        func record(_ pid: pid_t) { lock.lock(); values[pid, default: 0] += 1; lock.unlock() }
        func count(_ pid: pid_t) -> Int { lock.lock(); defer { lock.unlock() }; return values[pid, default: 0] }
    }
    @MainActor static func verify() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw NSError(domain: "TileLauncher.LaunchSettings", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait(_ condition: () -> Bool) throws {
            let end = Date().addingTimeInterval(2)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
            try require(condition(), "Launch settings fixture did not finish")
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.09)) }
        func found(_ app: AppItem) -> ApplicationSettingsMenu.Found {
            .init(element: AXUIElementCreateApplication(getpid()),
                  command: MenuCommand(appID: app.id, appName: app.name, path: [app.name, "Settings…"]))
        }
        let app = AppItem(id: "preview.launch", pid: 123581, name: "Launching", url: nil)
        let other = AppItem(id: "preview.other", pid: 123582, name: "Other", url: nil)
        var ready = false, trusted = true, started: UInt64 = 1
        let reads = Reads()
        func service(_ result: @escaping ApplicationSettingsMenu.Reader, delay: TimeInterval = 0.04) -> ApplicationSettingsMenu {
            ApplicationSettingsMenu(reader: result, retryMisses: false, trusted: { trusted }, launchWaitTimeout: delay,
                finishedLaunching: { _ in ready },
                processIdentity: { .init(pid: $0, startedSeconds: started, startedMicroseconds: 0) })
        }
        let success = service({ app, _, _ in reads.record(app.pid); return found(app) })
        for _ in 0..<20 { success.refresh(app: app) }
        try require(reads.count(app.pid) == 0, "Early activation queried AX before launch completion")
        success.didFinishLaunching(app: other)
        try require(reads.count(other.pid) == 0, "Unrelated launch started a query")
        ready = true
        success.didFinishLaunching(app: app)
        try wait { success.hasSettings(in: app) }
        for _ in 0..<10 { success.didFinishLaunching(app: app) }
        settle()
        try require(reads.count(app.pid) == 1, "Launch completion and fallback both queried")
        success.invalidate(pid: app.pid); ready = false
        success.refresh(app: app); success.didFinishLaunching(app: app); settle()
        try require(success.hasSettings(in: app) && reads.count(app.pid) == 1,
                    "Known support waited or re-read after app restart")

        let cancelledReads = Reads()
        let cancelled = service({ app, _, _ in cancelledReads.record(app.pid); return found(app) })
        cancelled.refresh(app: app)
        cancelled.refresh(app: other) // Cancels the old deferred target.
        cancelled.didFinishLaunching(app: app)
        cancelled.cancel(); settle()
        try require(cancelledReads.count(app.pid) == 0 && cancelledReads.count(other.pid) == 0,
                    "Changed/cancelled target was read after its launch event or deadline")
        cancelled.refresh(app: app); cancelled.invalidate(pid: app.pid)
        cancelled.didFinishLaunching(app: app); settle()
        try require(cancelledReads.count(app.pid) == 0, "Terminated launch wait survived invalidation")
        cancelled.refresh(app: app); started = 2
        cancelled.didFinishLaunching(app: app); settle()
        try require(cancelledReads.count(app.pid) == 0, "Deferred launch queried a reused PID")
        cancelled.refresh(app: app); trusted = false
        cancelled.didFinishLaunching(app: app); settle()
        try require(cancelledReads.count(app.pid) == 0, "Deferred read ignored revoked permission")
        trusted = true

        // Apps that never report launch completion still get one bounded read;
        // later completion notifications cannot turn it into an extra attempt.
        let fallbackReads = Reads()
        let fallback = service({ app, _, _ in fallbackReads.record(app.pid); return found(app) })
        fallback.refresh(app: app)
        try wait { fallback.hasSettings(in: app) }
        fallback.didFinishLaunching(app: app); settle()
        try require(fallbackReads.count(app.pid) == 1, "No-notification app hung or repeated fallback")

        // Deferral is not a failure, nor does a failed completed read retry on a
        // duplicate launch notification. Five real failed reads still stop.
        let failedReads = Reads()
        let failed = service({ app, _, _ in failedReads.record(app.pid); return nil })
        var changes = 0
        failed.onChange = { changes += 1 }
        for attempt in 1...5 {
            failed.refresh(app: app)
            if attempt > 1 { failed.didFinishLaunching(app: app) }
            try wait { changes == attempt }
            failed.didFinishLaunching(app: app); settle()
            try require(failedReads.count(app.pid) == attempt, "Deferral consumed a failure or launch event retried")
        }
        failed.refresh(app: app); failed.didFinishLaunching(app: app); settle()
        try require(changes == 5 && failedReads.count(app.pid) == 5, "Launch handling bypassed exhaustion")

        // Launch completion while a cancelled old lookup is running queues just
        // one new read, and never publishes the old app's late result.
        ready = true
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let serialReads = Reads()
        let serial = service({ app, _, _ in
            serialReads.record(app.pid)
            if app == other { entered.signal(); _ = release.wait(timeout: .now() + 1) }
            return found(app)
        })
        serial.refresh(app: other)
        try require(entered.wait(timeout: .now() + 1) == .success, "Old lookup did not start")
        ready = false
        serial.refresh(app: app)
        serial.didFinishLaunching(app: app); serial.didFinishLaunching(app: app)
        release.signal()
        try wait { serial.hasSettings(in: app) }
        settle()
        try require(!serial.hasSettings(in: other) && serialReads.count(app.pid) == 1 && serialReads.count(other.pid) == 1,
                    "Launch completion duplicated a queued read or published stale support")
        print("App settings launch: defer activation, one completion/fallback read, cache retention, cancelled/terminated/reused PID, permission, five-failure stop and serialized reads passed.")
    }
}
#endif
