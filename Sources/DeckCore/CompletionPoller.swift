import Foundation

/// Main-thread polling with at most one asynchronous read in flight. A repeat
/// is scheduled only after completion, so slow reads never build a work queue.
public final class CompletionPoller<Value> {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private let interval: TimeInterval
    private let operation: (@escaping (Value) -> Void) -> Void
    private let schedule: Schedule
    public var onValue: ((Value) -> Void)?
    private var running = false
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0
    private var inFlight: UInt64?
    private var scheduled: UInt64?
    private var cancelScheduled: (() -> Void)?

    /// `operation` may work in the background, but must complete on the main thread.
    public convenience init(interval: TimeInterval, operation: @escaping (@escaping (Value) -> Void) -> Void) {
        self.init(interval: interval, operation: operation) { delay, fire in
            let timer = Timer(timeInterval: delay, repeats: false) { _ in fire() }
            RunLoop.main.add(timer, forMode: .common)
            return { timer.invalidate() }
        }
    }

    init(interval: TimeInterval, operation: @escaping (@escaping (Value) -> Void) -> Void,
         schedule: @escaping Schedule) {
        precondition(interval > 0)
        self.interval = interval
        self.operation = operation
        self.schedule = schedule
    }

    deinit { cancelScheduled?() }

    /// Start once, or adopt an in-progress preparation read without duplicating it.
    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !running else { return }
        running = true
        refresh()
    }

    /// Cancel future reads and invalidate a late result. The in-flight gate is
    /// retained until its callback arrives, including across a quick stop/start.
    public func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        running = false
        generation &+= 1
        scheduled = nil
        cancelScheduled?()
        cancelScheduled = nil
    }

    /// One preparation read when stopped. Extra requests during a read or the
    /// repeat's resting interval are dropped, never added to a pending queue.
    public func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard inFlight == nil, scheduled == nil else { return }
        sequence &+= 1
        let readID = sequence, readGeneration = generation
        inFlight = readID
        operation { [weak self] value in
            dispatchPrecondition(condition: .onQueue(.main))
            guard let self, self.inFlight == readID else { return }
            self.inFlight = nil
            if self.generation == readGeneration { self.onValue?(value) }
            self.scheduleNext()
        }
    }

    private func scheduleNext() {
        guard running, inFlight == nil, scheduled == nil else { return }
        sequence &+= 1
        let timerID = sequence
        scheduled = timerID
        cancelScheduled = schedule(interval) { [weak self] in
            guard let self, self.running, self.scheduled == timerID else { return }
            self.scheduled = nil
            self.cancelScheduled = nil
            self.refresh()
        }
    }
}
