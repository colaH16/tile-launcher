import AppKit
import SwiftUI
import DeckCore

/// Observe only left clicks in this overlay. A transparent mouse-capturing layer
/// would steal wheel scrolling from the grids beneath its blank gaps.
struct OverlayDragHandle: NSViewRepresentable {
    let enabled: Bool
    var excludedRects: [CGRect] = []

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        if view.excludedRects != excludedRects { view.excludedRects = excludedRects }
        view.enabled = enabled
    }
    static func dismantleNSView(_ view: DragView, coordinator: ()) { view.enabled = false }

    final class DragView: NSView {
        var excludedRects: [CGRect] = []
        /// Synthetic native validation replaces the actual OS drag only.
        var beginDragForValidation: ((NSEvent) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var enabled = false {
            didSet { if oldValue != enabled { updateWindow() } }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindow()
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        private func updateWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            window?.isMovable = enabled
            window?.isMovableByWindowBackground = false
            setAccessibilityElement(false)
            guard enabled, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handleMouseDown(event)
            }
        }
        func canStartDrag(at point: NSPoint) -> Bool {
            enabled && !isHiddenOrHasHiddenAncestor
                && OverlayDragGeometry.canBegin(at: point, bounds: bounds, excluding: excludedRects)
        }
        func handleMouseDown(_ event: NSEvent) -> NSEvent? {
            guard event.type == .leftMouseDown, let window, event.window === window,
                  canStartDrag(at: convert(event.locationInWindow, from: nil)) else { return event }
            // Native scrollbars are controls too, including overlay scrollers.
            if let content = window.contentView {
                var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
                while let view = hit {
                    if view is NSScroller { return event }
                    hit = view.superview
                }
            }
            if let beginDragForValidation { beginDragForValidation(event) }
            else { window.performDrag(with: event) }
            return nil
        }
    }
}
