import Foundation

/// Session-only ordering. Unobserved items keep their supplied enumeration order.
public struct Recency<Key: Hashable> {
    private var order: [Key: UInt64] = [:]
    private var clock: UInt64 = 0
    public init() {}
    public mutating func touch(_ key: Key) {
        clock += 1
        order[key] = clock
    }
    public mutating func retain(_ keys: Set<Key>) { order = order.filter { keys.contains($0.key) } }
    public func sorted(_ keys: [Key]) -> [Key] {
        keys.enumerated().sorted {
            let lhs = order[$0.element, default: 0]
            let rhs = order[$1.element, default: 0]
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
    }
}

/// Tracks only Option state and cancellation; never stores typed characters.
public struct HoldGesture {
    public enum Effect: Equatable { case none, arm, cancel, release }
    private var optionDown = false
    private var cancelled = false
    public init() {}
    public mutating func flags(option: Bool, otherModifier: Bool, overlayVisible: Bool = false) -> Effect {
        if !option {
            let wasDown = optionDown
            optionDown = false
            cancelled = false
            return wasDown ? .release : .none
        }
        if !optionDown {
            optionDown = true
            if overlayVisible { cancelled = true; return .none }
            cancelled = otherModifier
            return otherModifier ? .cancel : .arm
        }
        if otherModifier && !cancelled && !overlayVisible {
            cancelled = true
            return .cancel
        }
        return .none
    }
    public mutating func interrupt() -> Effect {
        guard optionDown else { return .none }
        cancelled = true
        return .cancel
    }
}
