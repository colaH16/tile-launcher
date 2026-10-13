import AppKit

enum SettingsWindowLayout {
    static let defaultContentSize = CGSize(width: 580, height: 1000)
    @MainActor static func apply(to window: NSWindow, visibleFrame: NSRect?) {
        window.minSize = .zero
        window.setContentSize(defaultContentSize)
        if let visibleFrame {
            let available = visibleFrame.insetBy(dx: 24, dy: 24)
            var frame = window.frame
            frame.size.width = min(frame.width, available.width)
            frame.size.height = min(frame.height, available.height)
            window.setFrame(frame, display: false)
        }
        window.minSize = NSSize(width: min(540, window.frame.width), height: min(660, window.frame.height))
    }
}
