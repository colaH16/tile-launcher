import AppKit
import SwiftUI
import DeckCore

struct OverlayDragTarget {
    let id: String
    let rect: CGRect
    let action: (() -> Void)?
}

/// Native background responder, with separate tile responders for delayed drag.
/// Right clicks, hover and wheel events pass through to the SwiftUI controls.
struct OverlayDragHandle: NSViewRepresentable {
    let enabled: Bool
    var excludedRects: [CGRect] = []
    var targets: [OverlayDragTarget] = []

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.excludedRects = excludedRects
        view.enabled = enabled
        view.updateTargets(targets)
    }
    static func dismantleNSView(_ view: DragView, coordinator: ()) { view.enabled = false; view.cancelPress() }

    final class DragView: NSView {
        var excludedRects: [CGRect] = []
        var enabled = false {
            didSet {
                if enabled && !oldValue { window?.isMovable = true; window?.isMovableByWindowBackground = true }
                if !enabled { cancelPress() }
            }
        }
        #if TILE_LAUNCHER_DIAGNOSTICS
        var allowUnorderedActionsForValidation = false
        var targetsForValidation: [OverlayDragTarget] { ordered }
        #endif
        private var controls: [String: TileView] = [:]
        private var ordered: [OverlayDragTarget] = []
        private var bypassHitTesting = false
        private var pressedID: String?
        private var motion: OverlayDragMotion?
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Set once on attachment; never toggle either flag per mouse press.
            if enabled { window?.isMovable = true; window?.isMovableByWindowBackground = true }
            if window == nil { cancelPress() }
            setAccessibilityElement(false)
        }
        func updateTargets(_ targets: [OverlayDragTarget]) {
            ordered = targets
            let ids = Set(targets.map(\.id))
            if let pressedID, !ids.contains(pressedID) { cancelPress() }
            for id in Array(controls.keys) where !ids.contains(id) { controls.removeValue(forKey: id)?.removeFromSuperview() }
            for target in targets {
                let child: TileView
                if let existing = controls[target.id] { child = existing }
                else {
                    child = TileView(frame: target.rect); child.owner = self; child.id = target.id
                    controls[target.id] = child; addSubview(child)
                }
                if child.frame != target.rect { child.frame = target.rect }
                child.action = target.action
            }
        }
        func canStartDrag(at point: NSPoint) -> Bool {
            enabled && !isHiddenOrHasHiddenAncestor
                && OverlayDragGeometry.canBegin(at: point, bounds: bounds, excluding: excludedRects)
        }
        func nativeTarget(at point: CGPoint) -> NSView? {
            guard enabled, bounds.contains(point), !isHiddenOrHasHiddenAncestor else { return nil }
            if let target = ordered.last(where: { $0.rect.contains(point) }) { return controls[target.id] }
            return canStartDrag(at: point) ? self : nil
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !bypassHitTesting, let event = NSApp.currentEvent, !event.modifierFlags.contains(.control),
                  [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) else { return nil }
            let local = convert(point, from: superview)
            guard let target = nativeTarget(at: local) else { return nil }
            // Scroller tracking remains native, including overlay scrollers.
            if event.type == .leftMouseDown, let content = window?.contentView {
                bypassHitTesting = true
                var underlying = content.hitTest(content.convert(event.locationInWindow, from: nil))
                bypassHitTesting = false
                while let hit = underlying {
                    if hit is NSScroller { return nil }
                    underlying = hit.superview
                }
            }
            return target
        }
        func begin(_ event: NSEvent, id: String) {
            cancelPress()
            guard enabled, let window, event.window === window, controls[id] != nil else { return }
            pressedID = id
            motion = OverlayDragMotion(start: window.convertPoint(toScreen: event.locationInWindow),
                                       origin: window.frame.origin, backingScale: window.backingScaleFactor)
            controls[id]?.pressed = true
        }
        func drag(_ event: NSEvent, mayBegin: Bool = true) {
            guard let window, event.window === window, var motion else { return }
            let origin = motion.advance(to: window.convertPoint(toScreen: event.locationInWindow), mayBegin: mayBegin)
            self.motion = motion
            if motion.committed, let pressedID { controls[pressedID]?.pressed = false }
            if let origin, window.frame.origin != origin { window.setFrameOrigin(origin) }
        }
        func release(_ event: NSEvent) {
            guard let id = pressedID, let window, event.window === window else { cancelPress(); return }
            drag(event, mayBegin: false)
            let local = convert(event.locationInWindow, from: nil)
            var canExecute = window.isVisible
            #if TILE_LAUNCHER_DIAGNOSTICS
            canExecute = canExecute || allowUnorderedActionsForValidation
            #endif
            let action = motion?.committed == false && controls[id]?.frame.contains(local) == true
                && canExecute ? controls[id]?.action : nil
            cancelPress() // Clear tracking before an action hides/rebuilds the overlay.
            action?()
        }
        func cancelPress() {
            if let pressedID { controls[pressedID]?.pressed = false }
            pressedID = nil; motion = nil
        }
        final class TileView: NSView {
            weak var owner: DragView?
            var id = ""
            var action: (() -> Void)?
            var pressed = false { didSet { if oldValue != pressed { needsDisplay = true } } }
            override var isOpaque: Bool { false }
            override var mouseDownCanMoveWindow: Bool { false }
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func mouseDown(with event: NSEvent) { owner?.begin(event, id: id) }
            override func mouseDragged(with event: NSEvent) { owner?.drag(event) }
            override func mouseUp(with event: NSEvent) { owner?.release(event) }
            override func draw(_ dirtyRect: NSRect) {
                if pressed {
                    NSColor.white.withAlphaComponent(0.12).setFill()
                    NSBezierPath(rect: bounds).fill()
                }
            }
            override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); setAccessibilityElement(false) }
        }
    }
}
