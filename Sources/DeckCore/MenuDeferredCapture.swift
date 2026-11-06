import Foundation

/// Lifetime of a Help selection already confirmed by a physical release.
/// Row hit-testing and the existing release-to-notification gate belong to the
/// native adapter; this policy imposes no mouse-down-to-release time limit.
///
/// A caller must serialize access (one queue or its own lock). Resolver work
/// finishing is not a commit: `take` belongs immediately before the final save,
/// after rechecking current settings, policy and suppression on the native side.
public struct MenuDeferredCapture {
    public struct Ticket: Equatable {
        public let id: UInt64
        public let generation: UInt64
        public let confirmedAt: TimeInterval
        public let expiresAt: TimeInterval
    }

    public private(set) var pending: Ticket?
    private var lastID: UInt64 = 0

    public init() {}

    /// Starts a bounded resolver lifetime after a validated release. Every new
    /// selection supersedes the old one, including an invalid request (fail closed).
    /// IDs never wrap and are not reset by cancellation or a generation change.
    @discardableResult
    public mutating func confirm(generation: UInt64, at time: TimeInterval,
                                 duration: TimeInterval = 2) -> Ticket? {
        pending = nil
        guard time.isFinite, time >= 0, duration.isFinite, duration > 0,
              lastID < UInt64.max else { return nil }
        let expiry = time + duration
        guard expiry.isFinite, expiry > time else { return nil }
        lastID += 1
        let ticket = Ticket(id: lastID, generation: generation, confirmedAt: time, expiresAt: expiry)
        pending = ticket
        return ticket
    }

    /// A normal menu close does not cancel a selection already released inside
    /// its validated row. Unconfirmed mouse-down state is managed separately.
    public func menuClosed() {}

    /// Use for a new physical input/selection, process or generation change,
    /// settings cancellation, explicit cancellation and monitor stop.
    public mutating func cancel() { pending = nil }

    public func isCurrent(_ ticket: Ticket, generation: UInt64, at time: TimeInterval) -> Bool {
        time.isFinite && time >= 0 && pending == ticket && generation == ticket.generation
            && time >= ticket.confirmedAt && time <= ticket.expiresAt
    }

    /// Consumes exactly once. A late result for an older ticket cannot consume a
    /// newer selection. Rejected results leave any current ticket unchanged.
    @discardableResult
    public mutating func take(_ ticket: Ticket, generation: UInt64, at time: TimeInterval) -> Bool {
        guard isCurrent(ticket, generation: generation, at: time) else { return false }
        pending = nil
        return true
    }
}
