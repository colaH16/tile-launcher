import Foundation

/// Bounded recovery for startup/temporary AX failures. A generation invalidates
/// work queued for an old process, even if the OS later reuses its PID.
public struct MenuObservationLifecycle {
    public private(set) var process: ProcessIdentity?
    public private(set) var generation: UInt64 = 0
    public private(set) var isReady = false
    private var failures = 0
    public init() {}
    @discardableResult public mutating func begin(_ process: ProcessIdentity?) -> UInt64 {
        generation &+= 1
        self.process = process; failures = 0; isReady = false
        return generation
    }
    public func accepts(_ generation: UInt64) -> Bool { process != nil && self.generation == generation }
    public mutating func connected(generation: UInt64) {
        guard accepts(generation) else { return }
        isReady = true
    }
    public mutating func retryDelay(generation: UInt64) -> TimeInterval? {
        let delays: [TimeInterval] = [0.25, 0.75, 2, 5, 15]
        guard accepts(generation), !isReady, failures < delays.count else { return nil }
        defer { failures += 1 }
        return delays[failures]
    }
}
