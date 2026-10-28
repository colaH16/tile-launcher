import Foundation

/// A short, one-use location hint after an unselected held overlay is released.
/// Event timestamps share the same monotonic clock; display/timer latency is not
/// part of the interval. This is a convenience heuristic, not intent detection.
public struct OptionReopenMemory<Location> {
    private var closed: (time: TimeInterval, interval: TimeInterval, location: Location)?
    public init() {}

    public mutating func record(_ location: Location?, at time: TimeInterval,
                                reason: OverlayDismissal, held: Bool, actionPending: Bool,
                                preferences: OptionReopenPreferences = .init()) {
        closed = nil
        guard preferences.enabled, reason == .release, held, !actionPending,
              time.isFinite, let location else { return }
        closed = (time, preferences.interval, location)
    }

    public mutating func take(at time: TimeInterval, enabled: Bool = true) -> Location? {
        defer { cancel() }
        guard enabled, let closed, time.isFinite, time >= closed.time,
              time <= closed.time + closed.interval else { return nil }
        return closed.location
    }

    public mutating func cancel() { closed = nil }
}
