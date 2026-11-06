import AppKit
import DeckCore

final class HoldMonitor {
    /// Show/prepare/quick-reopen receive the cursor anchor sampled when this
    /// gesture's first valid Option press was detected, never a later position.
    var onShow: ((CGPoint) -> Void)?
    var onHide: ((OverlayDismissal, TimeInterval) -> Void)?
    var onQuickReopen: ((TimeInterval, CGPoint) -> Bool)?
    var onReopenCancelled: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRelease: (() -> Void)?
    var onShortcut: ((OverlayShortcut) -> Void)?
    /// Start building the overlay while the hold timer runs; abandon it if no overlay follows.
    var onPrepare: ((CGPoint) -> Void)?
    var onAbandon: (() -> Void)?
    var ownsKeyboard: (() -> Bool)?
    var canTriggerHold: (() -> Bool)?
    var hasPressedMouseButtons: () -> Bool = { NSEvent.pressedMouseButtons != 0 }
    /// AppKit global coordinates, read when the press is handled (detection
    /// time; not a hardware-timestamp sample). Injectable for native checks.
    var cursorLocation: () -> CGPoint = { NSEvent.mouseLocation }
    var isShowing = false
    private var gesture = HoldGesture()
    private var timer: DispatchWorkItem?
    private var global: Any?
    private var local: Any?
    private var triggered = false
    private(set) var optionDown = false

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in _ = self?.handle($0, external: true) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event, external: false) == true ? nil : event
        }
    }
    func stop() {
        onReopenCancelled?()
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
        timer?.cancel()
        timer = nil
        onAbandon?()
        triggered = false
        optionDown = false
        gesture = HoldGesture()
    }
    /// A true result consumes a local event; global events are never modified.
    /// Also used by NSPanel's key-equivalent route, which AppKit may use before keyDown.
    func handleOverlayShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isShowing, ownsKeyboard?() == true,
              let shortcut = OverlayShortcut.resolve(keyCode: event.keyCode, modifiers: modifiers(event)) else { return false }
        if !event.isARepeat {
            onCancel?()
            onShortcut?(shortcut)
        }
        return true
    }
    func handle(_ event: NSEvent, external: Bool) -> Bool {
        if event.type == .flagsChanged {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            optionDown = flags.contains(.option)
            let other = !flags.intersection([.command, .control, .shift, .function]).isEmpty
            apply(gesture.flags(option: optionDown, otherModifier: other, overlayVisible: isShowing), at: event.timestamp)
            if other { onReopenCancelled?() }
        } else if event.type == .keyDown {
            onReopenCancelled?()
            if !external, handleOverlayShortcut(event) { return true }
            apply(gesture.interrupt(), at: event.timestamp)
            if isShowing || event.keyCode == 53 {
                onHide?(event.keyCode == 53 ? .escape : .interruption, event.timestamp)
            }
        } else {
            onReopenCancelled?()
            if !isShowing {
                apply(gesture.interrupt(), at: event.timestamp)
            } else if external {
                onHide?(.outsideClick, event.timestamp)
                apply(gesture.interrupt(), at: event.timestamp)
            }
        }
        return false
    }
    private func modifiers(_ event: NSEvent) -> OverlayShortcut.Modifiers {
        var result: OverlayShortcut.Modifiers = []
        for (native, core): (NSEvent.ModifierFlags, OverlayShortcut.Modifiers) in [
            (.option, .option), (.command, .command), (.shift, .shift),
            (.control, .control), (.function, .function)
        ] where event.modifierFlags.contains(native) { result.insert(core) }
        return result
    }
    private func apply(_ effect: HoldGesture.Effect, at time: TimeInterval) {
        switch effect {
        case .none: break
        case .arm:
            guard canTriggerHold?() != false else { return }
            // Once per gesture, before any other work. The deferred prepare/show
            // capture this constant; nothing shared can leak into a later press.
            let anchor = cursorLocation()
            // Every arm/cancel/release/stop cancels the previous work item before
            // it runs, so a stale gesture can never show; prepare also checks identity.
            timer?.cancel()
            timer = nil
            if !hasPressedMouseButtons(), onQuickReopen?(time, anchor) == true {
                triggered = true
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.optionDown, self.canTriggerHold?() != false,
                      !self.hasPressedMouseButtons() else { self?.onAbandon?(); return }
                self.triggered = true
                self.onShow?(anchor)
            }
            timer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            // After this event is handled, so the monitor callback stays short.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.timer === work, !work.isCancelled, !self.isShowing else { return }
                self.onPrepare?(anchor)
            }
        case .cancel:
            onCancel?()
            timer?.cancel()
            timer = nil
            if triggered { onHide?(.interruption, time) } else { onAbandon?() }
        case .release:
            timer?.cancel()
            timer = nil
            if triggered { onHide?(.release, time) } else { onAbandon?() }
            triggered = false
            onRelease?()
        }
    }
}
