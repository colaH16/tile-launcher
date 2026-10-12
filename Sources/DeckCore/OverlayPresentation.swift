import Combine

public enum OverlayDismissal { case release, interruption, outsideClick, escape }

/// Pinning applies to this presentation only, including screenshot shortcuts.
public final class OverlayPresentation: ObservableObject {
    @Published public private(set) var isPinned = false
    @Published public var selection: String?
    public init() {}
    public func pin() { isPinned = true }
    public func reset() { isPinned = false; selection = nil }
    public func dismisses(for reason: OverlayDismissal) -> Bool {
        reason == .escape || !isPinned
    }
}
