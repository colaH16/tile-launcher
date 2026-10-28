import Foundation

public enum OverlayRefreshPolicy {
    /// R194: held (Option) and pinned overlays follow the active app/windows
    /// the same way. Holding Option no longer freezes the content: while the
    /// pointer is over the overlay to click, the user cannot switch windows.
    /// Only a pending number choice or a pressed mouse button defers a refresh,
    /// so the target being chosen or clicked never moves.
    public static func allows(hasSelection: Bool, hasPendingAction: Bool, mouseDown: Bool) -> Bool {
        !hasSelection && !hasPendingAction && !mouseDown
    }
}
