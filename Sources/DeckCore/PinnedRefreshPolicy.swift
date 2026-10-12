import Foundation

public enum PinnedRefreshPolicy {
    /// Stable targets while choosing; live content when a pinned panel is idle.
    public static func allows(isPinned: Bool, optionDown: Bool,
                              hasSelection: Bool, hasPendingAction: Bool,
                              mouseDown: Bool) -> Bool {
        isPinned && !optionDown && !hasSelection && !hasPendingAction && !mouseDown
    }
}
