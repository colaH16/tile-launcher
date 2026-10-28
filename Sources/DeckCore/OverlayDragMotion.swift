import Foundation

/// Physical screen pixels, independent of the overlay's UI scale.
public struct OverlayDragMotion {
    public let start: CGPoint
    public let origin: CGPoint
    public let pixels: CGFloat
    public let backingScale: CGFloat
    public private(set) var committed = false

    public init(start: CGPoint, origin: CGPoint, pixels: CGFloat = 7, backingScale: CGFloat) {
        self.start = start; self.origin = origin; self.pixels = pixels
        self.backingScale = max(1, backingScale)
    }
    public mutating func advance(to point: CGPoint, mayBegin: Bool = true) -> CGPoint? {
        if !committed {
            guard mayBegin, hypot(point.x - start.x, point.y - start.y) * backingScale >= pixels else { return nil }
            committed = true
        }
        return CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)
    }
}
