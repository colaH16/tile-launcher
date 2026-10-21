import AppKit
import SwiftUI
import DeckCore

struct OverlayDragTarget {
    let id: String
    let rect: CGRect
    let action: (() -> Void)?
    var circular = false
    var surfaceRect: CGRect?
    var cornerRadius: CGFloat?
}

/// Direct movement for empty background and thresholded tile responders.
/// Right clicks, hover and wheel events pass through to the SwiftUI controls.
struct OverlayDragHandle: NSViewRepresentable {
    let enabled: Bool
    var feedbackEnabled = false
    var squareSurface = false
    var excludedRects: [CGRect] = []
    var targets: [OverlayDragTarget] = []

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.excludedRects = excludedRects
        view.enabled = enabled
        view.feedbackEnabled = feedbackEnabled
        view.squareSurface = squareSurface
        view.updateTargets(targets)
    }
    static func dismantleNSView(_ view: DragView, coordinator: ()) { view.enabled = false; view.cancelPress() }

    final class DragView: NSView {
        var excludedRects: [CGRect] = []
        var enabled = false {
            didSet {
                if enabled && !oldValue { window?.isMovable = true; window?.isMovableByWindowBackground = false; window?.acceptsMouseMovedEvents = true }
                if !enabled { cancelPress(); updatePointerSurface() }
            }
        }
        #if TILE_LAUNCHER_DIAGNOSTICS
        var allowUnorderedActionsForValidation = false
        var targetsForValidation: [OverlayDragTarget] { ordered }
        var activeFeedbackFrameForValidation: CGRect? { feedback.superview == nil ? nil : feedback.frame }
        var activeFeedbackIDForValidation: String? { feedback.superview == nil ? nil : surfaceID }
        private(set) var feedbackPathBuildCountForValidation = 0
        func feedbackContainsForValidation(_ point: CGPoint) -> Bool {
            feedback.superview != nil && feedback.outline?.contains(feedback.convert(point, from: self)) == true
        }
        func pointerForValidation(_ point: CGPoint?) { pointerInside = point != nil; updatePointerSurface(at: point) }
        #endif
        private var controls: [String: TileView] = [:]
        private var ordered: [OverlayDragTarget] = []
        var feedbackEnabled = false { didSet { if oldValue != feedbackEnabled { updatePointerSurface() } } }
        var squareSurface = false
        private var tracking: NSTrackingArea?
        private var pointerInside = false
        private var surfaceID: String?
        private let feedback = FeedbackView()
        private var feedbackPaths: [String: (rect: CGRect, path: CGPath, rim: CGPath)] = [:]
        private var backgroundCutouts: [FeedbackShape] = []
        private var previousExcludedRects: [CGRect] = []
        private var previousSquareSurface = false
        private struct TargetGeometry: Equatable {
            let id: String
            let rect: CGRect
            let surfaceRect: CGRect?
            let radius: CGFloat?
            let circular: Bool
            let actionable: Bool
            init(_ target: OverlayDragTarget) {
                id = target.id; rect = target.rect; surfaceRect = target.surfaceRect
                radius = target.cornerRadius; circular = target.circular; actionable = target.action != nil
            }
        }
        // Visual silhouettes are independent of the rectangular input targets.
        // The feedback layer is above SwiftUI, so opaque controls cannot cover it.
        private struct FeedbackShape {
            let rect: CGRect
            var radius: CGFloat = 0
            var circular = false
            var clip: CGRect?
            var visibleRect: CGRect { clip.map { rect.intersection($0) } ?? rect }
            func path(relativeTo frame: CGRect) -> CGPath {
                let local = CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
                let path: CGPath
                if circular {
                    let side = min(local.width, local.height)
                    path = CGPath(ellipseIn: CGRect(x: local.midX - side / 2, y: local.midY - side / 2, width: side, height: side), transform: nil)
                } else { path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: local).cgPath }
                guard let clip else { return path }
                let clipped = CGRect(x: clip.minX - frame.minX, y: frame.maxY - clip.maxY, width: clip.width, height: clip.height)
                return path.intersection(CGPath(rect: clipped, transform: nil))
            }
        }
        private func silhouette(of target: OverlayDragTarget) -> FeedbackShape {
            let option = target.id.hasPrefix("menu-option:")
            let raw = target.surfaceRect ?? target.rect
            return FeedbackShape(rect: option ? raw.insetBy(dx: raw.height * 0.04, dy: raw.height * 0.04) : raw,
                                 radius: target.cornerRadius ?? (option && !squareSurface ? raw.height * 0.12 : 0),
                                 circular: target.circular, clip: target.rect)
        }
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
            if enabled {
                window?.isMovable = true; window?.isMovableByWindowBackground = false
                window?.acceptsMouseMovedEvents = true
            }
            if window == nil { cancelPress(); pointerInside = false; updatePointerSurface() }
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
            guard feedbackEnabled, enabled, pointerInside, let window,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                feedback.removeFromSuperview(); surfaceID = nil
                return
            }
            let point = supplied ?? convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard bounds.contains(point) else { feedback.removeFromSuperview(); surfaceID = nil; return }
            let hit = ordered.last(where: { $0.rect.contains(point) })
            if let hit, hit.action == nil { feedback.removeFromSuperview(); surfaceID = nil; return }
            // Native controls without an overlay action keep their own feedback.
            if hit == nil && !canStartDrag(at: point) { feedback.removeFromSuperview(); surfaceID = nil; return }
            let id = hit?.id ?? "background"
            let rect: CGRect
            let exclusions: [FeedbackShape]
            let shape: FeedbackShape
            if let target = hit {
                shape = silhouette(of: target)
                rect = shape.visibleRect
                guard !rect.isNull, !rect.isEmpty else { feedback.removeFromSuperview(); surfaceID = nil; return }
                exclusions = cutouts(for: target)
            } else {
                rect = bounds; exclusions = backgroundCutouts
                shape = FeedbackShape(rect: rect, radius: DeckSurfaceView.cornerRadius)
            }
            // Paths are made on layout changes / first entry only, never on
            // every mouse movement. Subtraction handles overlapping exclusions.
            let path: CGPath, rim: CGPath
            if let cached = feedbackPaths[id], cached.rect == rect { path = cached.path; rim = cached.rim }
            else {
                #if TILE_LAUNCHER_DIAGNOSTICS
                feedbackPathBuildCountForValidation += 1
                #endif
                let outside = shape.path(relativeTo: rect)
                var outline = outside
                for cutout in exclusions {
                    outline = outline.subtracting(cutout.path(relativeTo: rect))
                }
                path = outline; rim = outside; feedbackPaths[id] = (rect, path, rim)
            }
            if surfaceID != id || feedback.frame != rect || feedback.superview == nil {
                surfaceID = id; feedback.frame = rect; feedback.setOutline(path, rim: rim)
                if feedback.superview == nil { addSubview(feedback, positioned: .above, relativeTo: nil) }
            }
            feedback.follow(feedback.convert(point, from: self), pressed: motion?.committed != true && (pressedID == id || (hit == nil && motion != nil)), background: hit == nil)
        }
        private func cutouts(for target: OverlayDragTarget) -> [FeedbackShape] {
            guard target.id.hasPrefix("menu:") else { return [] }
            let optionID = target.id.replacingOccurrences(of: "menu:", with: "menu-option:")
            return ordered.filter { $0.id == optionID }.map { silhouette(of: $0) }
        }
        func updateTargets(_ targets: [OverlayDragTarget]) {
            let geometryChanged = targets.map(TargetGeometry.init) != ordered.map(TargetGeometry.init)
                || excludedRects != previousExcludedRects || squareSurface != previousSquareSurface
            ordered = targets
            // Bounds-only preferences duplicate most action regions. Do not
            // subtract their bounding boxes again over a shaped silhouette.
            if geometryChanged {
                previousExcludedRects = excludedRects; previousSquareSurface = squareSurface
                backgroundCutouts = excludedRects.filter { rect in !targets.contains(where: { $0.rect == rect }) }
                    .map { FeedbackShape(rect: $0) } + targets.map { silhouette(of: $0) }
                feedbackPaths.removeAll(keepingCapacity: true)
                surfaceID = nil
            }
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
                if geometryChanged {
                    child.outline = silhouette(of: target).path(relativeTo: target.rect)
                    child.cutouts = cutouts(for: target).map { $0.path(relativeTo: target.rect) }
                    if child.pressed { child.needsDisplay = true }
                }
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
            pointerInside = true; updatePointerSurface(at: convert(event.locationInWindow, from: nil))
        }
        func begin(_ event: NSEvent, id: String) {
            cancelPress()
            guard enabled, let window, event.window === window, controls[id] != nil else { return }
            pressedID = id
            motion = OverlayDragMotion(start: window.convertPoint(toScreen: event.locationInWindow),
                                       origin: window.frame.origin, backingScale: window.backingScaleFactor)
            controls[id]?.pressed = true
            pointerInside = true; updatePointerSurface(at: convert(event.locationInWindow, from: nil))
        }
        func drag(_ event: NSEvent, mayBegin: Bool = true) {
            guard let window, event.window === window, var motion else { return }
            let origin = motion.advance(to: window.convertPoint(toScreen: event.locationInWindow), mayBegin: mayBegin)
            self.motion = motion
            if motion.committed, let pressedID {
                controls[pressedID]?.pressed = false
                feedback.setPressed(false)
            }
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
            feedback.setPressed(false)
        }
        final class FeedbackView: NSView {
            private let clip = CAShapeLayer()
            private let rim = CAShapeLayer()
            private let sheen = CAGradientLayer()
            private let wash = CALayer()
            private(set) var outline: CGPath?
            private var isBackground = false
            private var phase: Int?
            override var isOpaque: Bool { false }
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
            override init(frame: CGRect) {
                super.init(frame: frame)
                wantsLayer = true; layer?.mask = clip
                layer?.addSublayer(wash); layer?.addSublayer(sheen); layer?.addSublayer(rim)
                sheen.type = .radial; sheen.locations = [0, 1]
                rim.fillColor = NSColor.clear.cgColor; rim.lineWidth = 1
                setAccessibilityElement(false)
            }
            required init?(coder: NSCoder) { nil }
            func setOutline(_ path: CGPath, rim outside: CGPath) {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                outline = path; clip.frame = bounds; clip.path = path
                sheen.frame = bounds; wash.frame = bounds; rim.frame = bounds
                // The mask excludes Option, but that inner cutout is not a
                // separate border belonging to the main tile.
                rim.path = outside
                CATransaction.commit()
            }
            func follow(_ point: CGPoint, pressed: Bool, background: Bool) {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let center = CGPoint(x: point.x / max(1, bounds.width), y: point.y / max(1, bounds.height))
                let radius: CGFloat = background ? 170 : min(105, max(bounds.width, bounds.height))
                sheen.startPoint = center
                sheen.endPoint = CGPoint(x: center.x + radius / max(1, bounds.width), y: center.y + radius / max(1, bounds.height))
                isBackground = background
                setPressed(pressed)
                CATransaction.commit()
            }
            func setPressed(_ pressed: Bool) {
                let next = (isBackground ? 2 : 0) + (pressed ? 1 : 0)
                guard phase != next else { return }
                phase = next
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let background = isBackground
                sheen.colors = [NSColor.white.withAlphaComponent(pressed ? 0.22 : background ? 0.12 : 0.14).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
                wash.backgroundColor = NSColor.white.withAlphaComponent(background ? 0 : pressed ? 0.06 : 0.02).cgColor
                rim.strokeColor = NSColor.white.withAlphaComponent(background ? 0 : pressed ? 0.42 : 0.20).cgColor
                CATransaction.commit()
            }
        }
        final class TileView: NSView {
            weak var owner: DragView?
            var id = ""
            var action: (() -> Void)?
            var circular = false
            var outline: CGPath?
            var cutouts: [CGPath] = []
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
                    var path = outline ?? (circular ? CGPath(ellipseIn: bounds, transform: nil) : CGPath(rect: bounds, transform: nil))
                    for cutout in cutouts { path = path.subtracting(cutout) }
                    if let context = NSGraphicsContext.current?.cgContext {
                        context.addPath(path); context.fillPath()
                    }
                }
            }
            override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); setAccessibilityElement(false) }
        }
    }
}
