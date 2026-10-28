import Foundation

/// Additional background reads after a failed scan. Never used for actions.
public struct AXReadRetryBudget {
    private var attempts = 0
    public init() {}
    public mutating func nextDelay() -> TimeInterval? {
        let delays: [TimeInterval] = [0.35, 1.0]
        guard attempts < delays.count else { return nil }
        defer { attempts += 1 }
        return delays[attempts]
    }
    public mutating func reset() { attempts = 0 }
}
