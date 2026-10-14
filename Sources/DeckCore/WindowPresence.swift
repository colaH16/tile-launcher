import CoreGraphics

/// Transparent utility surfaces aren't evidence of another desktop's window.
/// AX timeouts and missing inventory aren't proof that an app is windowless.
public enum WindowPresence {
    public static func serverCandidate(alpha: Double, bounds: CGRect) -> Bool {
        alpha.isFinite && alpha > 0 && bounds.width >= 80 && bounds.height >= 50
    }
    public static func applicationOnly(axComplete: Bool, inventoryComplete: Bool,
                                       accessibleWindows: Int, serverCandidates: Int) -> Bool {
        axComplete && inventoryComplete && accessibleWindows == 0 && serverCandidates == 0
    }
}
