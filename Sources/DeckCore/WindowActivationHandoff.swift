/// NSApplication and NSRunningApplication may temporarily disagree during a
/// turn of the main run loop. Wait for the workspace to confirm the source.
public enum WindowActivationHandoff {
    case wait, cooperative, fallback
    public static func evaluate(sourceActive: Bool, sourceFrontmost: Bool, targetActive: Bool,
                                attempt: Int) -> Self {
        if attempt > 0 && sourceActive && sourceFrontmost && !targetActive { return .cooperative }
        return attempt < 8 ? .wait : .fallback
    }
}
