import Foundation

/// A launched or activated app may expose its first window only after a
/// successful empty AX read, with no later notification. A few completion-based
/// rereads of that one process recover it; this is never periodic polling.
public struct WindowSettleBudget {
    public static let delays: [TimeInterval] = [0.3, 0.8, 1.6, 3.2]
    private var attempts = 0
    public init() {}
    public mutating func next(realWindowAccepted: Bool, processAlive: Bool, tracking: Bool) -> TimeInterval? {
        guard tracking, processAlive, !realWindowAccepted, attempts < Self.delays.count else {
            attempts = Self.delays.count
            return nil
        }
        defer { attempts += 1 }
        return Self.delays[attempts]
    }
}

/// One bounded settle sequence per process. All calls, scheduled work and the
/// read happen on the caller's serial queue; the read refreshes only `pid`.
public final class WindowSettleScheduler {
    public typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    private final class Entry {
        var budget = WindowSettleBudget()
        let isAlive: () -> Bool
        var running = true
        init(isAlive: @escaping () -> Bool) { self.isAlive = isAlive }
    }
    private var entries: [Int32: Entry] = [:]
    private let schedule: Schedule
    private let tracking: (Int32) -> Bool
    private let read: (Int32) -> Bool

    /// `read` refreshes and publishes one process and reports whether it now
    /// has an accepted real window (including a usable other-desktop tile).
    public init(schedule: @escaping Schedule, tracking: @escaping (Int32) -> Bool, read: @escaping (Int32) -> Bool) {
        self.schedule = schedule; self.tracking = tracking; self.read = read
    }

    /// Repeated launch/activation events for the same living process never
    /// start another allowance, whether its sequence is running or finished.
    @discardableResult
    public func arm(_ pid: Int32, hasRealWindow: Bool, isAlive: @escaping () -> Bool) -> Bool {
        if let existing = entries[pid], existing.isAlive() { return false }
        entries[pid] = nil
        guard !hasRealWindow, isAlive(), tracking(pid) else { return false }
        let entry = Entry(isAlive: isAlive)
        entries[pid] = entry
        scheduleNext(pid, entry, realWindowAccepted: false)
        return entry.running
    }
    public func isRunning(_ pid: Int32) -> Bool { entries[pid]?.running == true }
    /// Process removal; a later process with this PID may arm again.
    public func cancel(_ pid: Int32) { entries[pid] = nil }
    /// Trust or tracking loss.
    public func cancelAll() { entries.removeAll() }

    private func scheduleNext(_ pid: Int32, _ entry: Entry, realWindowAccepted: Bool) {
        guard let delay = entry.budget.next(realWindowAccepted: realWindowAccepted,
                                            processAlive: entry.isAlive(), tracking: tracking(pid)) else {
            entry.running = false
            return
        }
        schedule(delay) { [weak self, weak entry] in
            guard let self, let entry, self.entries[pid] === entry, entry.running else { return }
            guard entry.isAlive(), self.tracking(pid) else { entry.running = false; return }
            let accepted = self.read(pid)
            guard self.entries[pid] === entry else { return }
            self.scheduleNext(pid, entry, realWindowAccepted: accepted)
        }
    }
}

/// `AXObserverAddNotification` outcome, from the raw `AXError` code (a Debug
/// native check compares these values with the SDK enum).
public enum AXNotificationRegistration: Equatable {
    case registered, unsupported, transient
    public init(errorCode: Int32) {
        switch errorCode {
        case 0, -25209: self = .registered      // success, notificationAlreadyRegistered
        case -25207, -25208: self = .unsupported // notificationUnsupported, notImplemented
        default: self = .transient               // e.g. cannotComplete, failure during launch
        }
    }
    /// Names that still need another attempt. Registered or unsupported names
    /// are never re-added, so subscriptions are not duplicated or retried forever.
    public static func pending(_ results: [(name: String, code: Int32)]) -> [String] {
        results.filter { AXNotificationRegistration(errorCode: $0.code) == .transient }.map(\.name)
    }
}
