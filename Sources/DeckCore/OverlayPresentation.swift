import Combine
import Foundation

public enum OverlayDismissal { case release, interruption, outsideClick, escape }

public struct ShortcutExecution: Equatable {
    public let id = UUID()
    public let target: String
    public let title: String
}

/// Pinning applies to this presentation only, including screenshot shortcuts.
public final class OverlayPresentation: ObservableObject {
    @Published public private(set) var isPinned = false
    @Published public var selection: String? { didSet { if selection == nil { selectionTitle = nil } } }
    @Published public var selectionTitle: String?
    @Published public private(set) var execution: ShortcutExecution?
    @Published public var profile: LauncherProfile?
    // Desktop tint can update even when selection temporarily freezes tile order.
    @Published public var windowDesktops: [UUID: WindowDesktop] = [:]
    public init() {}
    public func pin() { isPinned = true }
    public func reset() { isPinned = false; selection = nil; execution = nil; profile = nil; windowDesktops = [:] }
    @discardableResult public func showExecution(target: String, title: String) -> UUID {
        let feedback = ShortcutExecution(target: target, title: title)
        execution = feedback
        return feedback.id
    }
    public func clearExecution(id: UUID? = nil) {
        if id == nil || execution?.id == id { execution = nil }
    }
    public func dismisses(for reason: OverlayDismissal) -> Bool {
        reason == .escape || !isPinned
    }
}
