import AppKit
import SwiftUI
import DeckCore

struct OverlayDragTarget {
    let id: String
    let rect: CGRect
    let action: (() -> Void)?
    var circular = false
}

/// Direct movement for empty background and thresholded tile responders.
/// Right clicks, hover and wheel events pass through to the SwiftUI controls.
struct OverlayDragHandle: NSViewRepresentable {
    let enabled: Bool
    var liquidSurface = false
    var squareSurface = false
    var excludedRects: [CGRect] = []
    var targets: [OverlayDragTarget] = []

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.excludedRects = excludedRects
        view.enabled = enabled
        view.liquidSurface = liquidSurface
        view.squareSurface = squareSurface
        view.updateTargets(targets)
    }
    static func dismantleNSView(_ view: DragView, coordinator: ()) { view.enabled = false; view.cancelPress() }

    final class DragView: NSView {
        var excludedRects: [CGRect] = []
        var enabled = false {
            didSet {
                if enabled && !oldValue { window?.isMovable = true; window?.isMovableByWindowBackground = false }
                if !enabled { cancelPress() }
            }
        }
        #if TILE_LAUNCHER_DIAGNOSTICS
        var allowUnorderedActionsForValidation = false
        var targetsForValidation: [OverlayDragTarget] { ordered }
        var activeGlassFrameForValidation: CGRect? { hoverGlass?.superview == nil ? nil : hoverGlass?.frame }
        func pointerForValidation(_ point: CGPoint?) { pointerInside = point != nil; updatePointerSurface(at: point) }
        #endif
        private var controls: [String: TileView] = [:]
        private var ordered: [OverlayDragTarget] = []
        var liquidSurface = false { didSet { if oldValue != liquidSurface { updatePointerSurface() } } }
        var squareSurface = false
        private var tracking: NSTrackingArea?
        private var pointerInside = false
        private var surfaceID: String?
        private var hoverGlass: NSGlassEffectView?
        private let sheen = CAGradientLayer()
        private var bypassHitTesting = false
        private var pressedID: String?
        private var motion: OverlayDragMotion?
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Set once on attachment; never toggle either flag per mouse press.
            if enabled { window?.isMovable = true; window?.isMovableByWindowBackground = false }
            if window == nil { cancelPress() }
            setAccessibilityElement(false)
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
            addTrackingArea(area); tracking = area
        }
        override func mouseEntered(with event: NSEvent) { pointerInside = true; updatePointerSurface() }
        override func mouseMoved(with event: NSEvent) { pointerInside = true; updatePointerSurface() }
        override func mouseExited(with event: NSEvent) { pointerInside = false; updatePointerSurface() }
        private func updatePointerSurface(at supplied: CGPoint? = nil) {
            var ancestor = superview
            while let node = ancestor, !(node is DeckSurfaceView) { ancestor = node.superview }
            guard liquidSurface, enabled, pointerInside, let window,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                hoverGlass?.removeFromSuperview(); surfaceID = nil
                (ancestor as? DeckSurfaceView)?.setBackgroundInteractive(false)
                return
            }
            let point = supplied ?? convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let hit = ordered.last(where: { $0.rect.contains(point) })
            (ancestor as? DeckSurfaceView)?.setBackgroundInteractive(hit == nil && bounds.contains(point))
            guard var target = hit else { hoverGlass?.removeFromSuperview(); surfaceID = nil; return }
            if target.id.hasPrefix("menu-option:"),
               let main = ordered.first(where: { $0.id == target.id.replacingOccurrences(of: "menu-option:", with: "menu:") }) { target = main }
            // A single reusable native effect, only over the hovered tile.
            // Pointer motion never rebuilds the SwiftUI tree or all tile effects.
            if hoverGlass == nil {
                let glass = NSGlassEffectView(frame: .zero)
                glass.style = .clear; glass.contentView = NSView()
                glass.contentView?.wantsLayer = true
                sheen.type = .radial
                sheen.colors = [NSColor.white.withAlphaComponent(0.24).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
                sheen.locations = [0, 1]
                glass.contentView?.layer?.addSublayer(sheen)
                if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
                glass.setAccessibilityElement(false); hoverGlass = glass
            }
            guard let glass = hoverGlass else { return }
            if surfaceID != target.id || glass.frame != target.rect || glass.superview == nil {
                surfaceID = target.id; glass.frame = target.rect
                glass.cornerRadius = target.circular ? min(target.rect.width, target.rect.height) / 2 : squareSurface ? 0 : min(14, target.rect.height / 6)
                if glass.superview == nil { addSubview(glass, positioned: .above, relativeTo: nil) }
            }
            // Only one small surface changes with pointer input. No timers,
            // display-link loop, or per-move SwiftUI state is required.
            CATransaction.begin(); CATransaction.setDisableActions(true)
            sheen.frame = CGRect(origin: .zero, size: target.rect.size)
            let local = CGPoint(x: (point.x - target.rect.minX) / max(1, target.rect.width),
                                y: 1 - (point.y - target.rect.minY) / max(1, target.rect.height))
            sheen.startPoint = local
            sheen.endPoint = CGPoint(x: local.x + 0.65, y: local.y + 0.65)
            CATransaction.commit()
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
                child.circular = target.circular
            }
            updatePointerSurface()
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
        override func mouseDown(with event: NSEvent) { beginBackground(event) }
        override func mouseDragged(with event: NSEvent) { drag(event) }
        override func mouseUp(with event: NSEvent) { release(event) }
        func beginBackground(_ event: NSEvent) {
            cancelPress()
            guard enabled, let window, event.window === window,
                  canStartDrag(at: convert(event.locationInWindow, from: nil)) else { return }
            motion = OverlayDragMotion(start: window.convertPoint(toScreen: event.locationInWindow),
                                       origin: window.frame.origin, pixels: 0, backingScale: window.backingScaleFactor)
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
            guard let window, event.window === window, motion != nil else { cancelPress(); return }
            drag(event, mayBegin: false)
            guard let id = pressedID else { cancelPress(); return }
            let local = convert(event.locationInWindow, from: nil)
            var canExecute = window.isVisible
            #if TILE_LAUNCHER_DIAGNOSTICS
            canExecute = canExecute || allowUnorderedActionsForValidation
            #endif
            let action = motion?.committed == false && controls[id]?.frame.contains(local) == true
                && nativeTarget(at: local) === controls[id] && canExecute ? controls[id]?.action : nil
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
            var circular = false
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
                    (circular ? NSBezierPath(ovalIn: bounds) : NSBezierPath(rect: bounds)).fill()
                }
            }
            override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); setAccessibilityElement(false) }
        }
    }
}
