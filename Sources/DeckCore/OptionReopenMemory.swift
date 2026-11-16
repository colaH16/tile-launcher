import Foundation

/// A short, one-use location hint after a held overlay is closed by releasing
/// Option, whether or not something was run while it was open (D-037-1).
/// Event timestamps share the same monotonic clock; display/timer latency is not
/// part of the interval. This is a convenience heuristic, not intent detection.
public struct OptionReopenMemory<Location> {
    private var closed: (time: TimeInterval, interval: TimeInterval, location: Location)?
    public init() {}

    public mutating func record(_ location: Location?, at time: TimeInterval,
                                reason: OverlayDismissal, held: Bool,
                                preferences: OptionReopenPreferences = .init()) {
        closed = nil
        guard preferences.enabled, reason == .release, held,
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
