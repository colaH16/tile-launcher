import Foundation

public enum ApplicationLaunchStatus: Equatable {
    case waiting, launching, finished, notStarted, stopped, timedOut, failed
    public var blocksLaunch: Bool { self == .waiting || self == .launching }
}

/// Monotonic time; each launch attempt owns its own instance and identity.
public struct ApplicationLaunchGate {
    public static let startTimeout: TimeInterval = 3
    public static let completionTimeout: TimeInterval = 60
    private let requestedAt: TimeInterval
    private var startedAt: TimeInterval?
    public private(set) var status: ApplicationLaunchStatus = .waiting
    public init(now: TimeInterval) { requestedAt = now }

    @discardableResult public mutating func update(processFound: Bool, finished: Bool = false,
        terminated: Bool = false, failed: Bool = false, now: TimeInterval) -> ApplicationLaunchStatus {
        guard status.blocksLaunch else { return status }
        if failed { status = .failed }
        else if terminated { status = .stopped }
        else if processFound && finished { status = .finished }
        else if processFound {
            if startedAt == nil { startedAt = now }
            status = now - (startedAt ?? now) >= Self.completionTimeout ? .timedOut : .launching
        } else if let startedAt {
            // A transient inventory gap is not evidence that a process stopped.
            status = now - startedAt >= Self.completionTimeout ? .timedOut : .launching
        } else if now - requestedAt >= Self.startTimeout { status = .notStarted }
        return status
    }
}
