import Foundation

public enum OverlayDragGeometry {
    /// A scrolled-out tile must not reserve a hit region in a header/footer.
    public static func clipped(_ rect: CGRect, to viewports: [CGRect]) -> CGRect? {
        var result = rect
        for viewport in viewports { result = result.intersection(viewport) }
        guard !result.isNull, !result.isInfinite, result.width > 0, result.height > 0 else { return nil }
        return result
    }
    public static func canBegin(at point: CGPoint, bounds: CGRect, excluding controls: [CGRect]) -> Bool {
        bounds.contains(point) && !controls.contains { $0.contains(point) }
    }
}
