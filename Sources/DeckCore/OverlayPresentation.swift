import Combine
import Foundation

public enum OverlayDismissal { case release, interruption, outsideClick, escape, windowSelection, spaceChange }

/// What running an item does to the overlay (spec 2절 닫히는 규칙).
public enum OverlayAction {
    /// App, window, menu (app settings included), Handoff, file: keeps an
    /// Option-held overlay, closes a pinned one (D-034-3, D-066-1).
    case run
    /// Finder folder, Trash, permission page: closes in either state (D-066-1).
    case leave
    /// Windowless app quit: never closes, so several can be quit in a row (D-043-2).
    case quit
}

public struct ShortcutExecution: Equatable {
    public let id = UUID()
    public let target: String
    public let title: String
}

/// Pinning applies to this presentation only, including screenshot shortcuts.
public final class OverlayPresentation: ObservableObject {
    @Published public private(set) var isPinned = false
    @Published public private(set) var execution: ShortcutExecution?
    @Published public var profile: LauncherProfile?
    // Desktop tint can update even when selection temporarily freezes tile order.
    @Published public var windowDesktops: [UUID: WindowDesktop] = [:]
    public init() {}
    public func pin() { isPinned = true }
    public func reset() { isPinned = false; execution = nil; profile = nil; windowDesktops = [:] }
    @discardableResult public func showExecution(target: String, title: String) -> UUID {
        let feedback = ShortcutExecution(target: target, title: title)
        execution = feedback
        return feedback.id
    }
    public func clearExecution(id: UUID? = nil) {
        if id == nil || execution?.id == id { execution = nil }
    }
    /// Clicks and ⌥+number share this: Option held keeps, pinned closes.
    public func closesAfterAction(_ action: OverlayAction) -> Bool {
        switch action {
        case .run: return isPinned
        case .leave: return true
        case .quit: return false
        }
    }
    /// Window/desktop transitions keep only an overlay that Option itself is
    /// still holding open. A manually opened overlay ignores a coincidental
    /// Option key, because releasing it will not close that overlay.
    public func dismisses(for reason: OverlayDismissal, heldPresentation: Bool = false,
                          optionDown: Bool = false) -> Bool {
        switch reason {
        case .escape: return true
        case .windowSelection, .spaceChange: return !isPinned && !(heldPresentation && optionDown)
        default: return !isPinned
        }
    }
}
