import AppKit
import ApplicationServices

/// Product discovery only: three independent readers, first confirmed Settings wins.
/// A shared pool leaves capacity for foreground discovery while launch reads
/// are awaiting IPC. Each app still races only the selected three routes.
enum AppSettingsRaceReader {
    static let routes: [AppSettingsRoute] = [.multiple, .children, .roleFirst]
    typealias Reader = (AppSettingsRoute, TimeInterval, () -> Bool) throws -> ApplicationSettingsMenu.Found?
    private static let workers: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "TileLauncher.settings-race"; queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 12
        return queue
    }()
    private final class State {
        private let lock = NSLock()
        let signal = DispatchSemaphore(value: 0)
        private var stopped = false
        private var found: ApplicationSettingsMenu.Found?
        private var completed = 0
        private var error: Error?
        var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        func stop() { lock.lock(); stopped = true; lock.unlock() }
        func finish(_ value: ApplicationSettingsMenu.Found?, error failure: Error?, cancelled: Bool) -> Bool {
            lock.lock(); defer { lock.unlock() }
            completed += 1
            if let value, !stopped, !cancelled { found = value; stopped = true; return true }
            if error == nil, let failure { error = failure }
            return false
        }
        var result: (ApplicationSettingsMenu.Found?, Int, Error?) {
            lock.lock(); defer { lock.unlock() }; return (found, completed, error)
        }
    }
    static func find(in app: AppItem, deadline: TimeInterval, cancelled: @escaping () -> Bool,
                     reader: Reader? = nil) throws -> ApplicationSettingsMenu.Found? {
        let state = State()
        for route in routes {
            workers.addOperation {
                let stop = { cancelled() || state.isStopped }
                var value: ApplicationSettingsMenu.Found?, error: Error?
                do {
                    guard !stop() else { throw ApplicationSettingsMenu.ReadError.cancelled }
                    guard ProcessInfo.processInfo.systemUptime < deadline else { throw ApplicationSettingsMenu.ReadError.deadline }
                    if let reader { value = try reader(route, deadline, stop) }
                    else {
                        let access = AppSettingsAXAccess(deadline: deadline, cancelled: stop)
                        if let bar = try access.menuBar(route: route, app: app) {
                            value = try ApplicationSettingsMenu.find(in: app, deadline: deadline,
                                isCancelled: stop, menuBar: bar)
                        }
                    }
                } catch let failure { error = failure }
                _ = state.finish(value, error: error, cancelled: stop())
                state.signal.signal()
            }
        }
        while true {
            guard !cancelled() else { state.stop(); throw ApplicationSettingsMenu.ReadError.cancelled }
            let (found, completed, error) = state.result
            if let found { return found }
            if completed == routes.count {
                if let error { throw error }
                return nil
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { state.stop(); throw ApplicationSettingsMenu.ReadError.deadline }
            // AX IPC already in flight cannot be forcibly interrupted. Readers
            // check the shared cancellation flag before each subsequent AX call.
            _ = state.signal.wait(timeout: .now() + min(0.02, remaining))
        }
    }
}
