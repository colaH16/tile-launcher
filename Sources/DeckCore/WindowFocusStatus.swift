/// Accepted AX/AppKit requests are not proof that a particular window is active.
public enum WindowFocusStatus: Equatable {
    case confirmed, retry, closed, unconfirmed

    public static func evaluate(targetExists: Bool?, frontmost: Bool, focused: Bool,
                                desktop: WindowDesktop, attempt: Int) -> Self {
        if targetExists == false { return .closed }
        if frontmost && focused && desktop != .other { return .confirmed }
        return attempt < 7 ? .retry : .unconfirmed
    }
}
