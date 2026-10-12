import Foundation

public enum ProfileNavigation {
    public static func target(in profiles: [LauncherProfile], currentID: String, step: Int) -> LauncherProfile? {
        guard profiles.count > 1, step != 0,
              let index = profiles.firstIndex(where: { $0.id == currentID }) else { return nil }
        let next = (index + (step > 0 ? 1 : -1) + profiles.count) % profiles.count
        return profiles[next]
    }
}

/// One horizontal swipe advances one profile. Vertical scrolling and momentum
/// never advance profiles. Device inversion is removed to follow physical direction.
public struct ProfileScrollGesture {
    public struct Result {
        public let consume: Bool
        public let step: Int?
    }
    private enum Axis { case undecided, horizontal, vertical }
    private var axis: Axis = .undecided
    private var totalX = 0.0, totalY = 0.0
    private var fired = false
    private var lastTime = -Double.infinity
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func scroll(x: Double, y: Double, precise: Bool, inverted: Bool,
                                time: Double, began: Bool, ended: Bool,
                                phased: Bool, momentum: Bool, cancelled: Bool = false) -> Result {
        if cancelled {
            let consume = axis == .horizontal
            reset()
            return Result(consume: consume, step: nil)
        }
        if momentum { return Result(consume: axis == .horizontal, step: nil) }
        if began || (!phased && time - lastTime > 0.3) { reset() }
        lastTime = time
        totalX += inverted ? -x : x
        totalY += y
        if axis == .undecided {
            let threshold = precise ? 8.0 : 0.5
            if abs(totalX) >= threshold && abs(totalX) > abs(totalY) * 1.35 { axis = .horizontal }
            else if abs(totalY) >= threshold && abs(totalY) >= abs(totalX) { axis = .vertical }
        }
        let consume = axis == .horizontal
        var step: Int?
        if consume && !fired && abs(totalX) >= (precise ? 48 : 1) {
            fired = true
            step = totalX > 0 ? 1 : -1 // Physical left goes to the next profile.
        }
        // Preserve the axis after end so momentum can be consumed, but cannot turn a page.
        if ended { fired = true }
        return Result(consume: consume, step: step)
    }
}
