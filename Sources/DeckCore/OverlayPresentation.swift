import Combine
import Foundation

public enum OverlayDismissal { case release, interruption, outsideClick, escape }

/// Pinning applies to this presentation only, including screenshot shortcuts.
public final class OverlayPresentation: ObservableObject {
    @Published public private(set) var isPinned = false
    @Published public var selection: String?
    @Published public var profile: LauncherProfile?
    // Only the desktop tint changes while pinned; tile identities/order stay frozen.
    @Published public var windowDesktops: [UUID: WindowDesktop] = [:]
    public init() {}
    public func pin() { isPinned = true }
    public func reset() { isPinned = false; selection = nil; profile = nil; windowDesktops = [:] }
    public func dismisses(for reason: OverlayDismissal) -> Bool {
        reason == .escape || !isPinned
    }
}
