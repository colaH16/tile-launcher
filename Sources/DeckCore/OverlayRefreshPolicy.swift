import Foundation

public enum OverlayRefreshPolicy {
    /// R194: held (Option) and pinned overlays follow the active app/windows
    /// the same way. Holding Option no longer freezes the content: while the
    /// pointer is over the overlay to click, the user cannot switch windows.
    /// Only shortcut execution feedback or a pressed mouse button defers a
    /// refresh, so the target just run or being clicked never moves.
    public static func allows(showsExecution: Bool, mouseDown: Bool) -> Bool {
        !showsExecution && !mouseDown
    }
}
