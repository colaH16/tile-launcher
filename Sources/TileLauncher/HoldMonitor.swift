import AppKit
import DeckCore

final class HoldMonitor {
    var onShow: (() -> Void)?
    var onHide: ((OverlayDismissal) -> Void)?
    var onCancel: (() -> Void)?
    var onRelease: (() -> Void)?
    var onShortcut: ((OverlayShortcut) -> Void)?
    var ownsKeyboard: (() -> Bool)?
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
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
        timer?.cancel()
        timer = nil
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
    private func handle(_ event: NSEvent, external: Bool) -> Bool {
        if event.type == .flagsChanged {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            optionDown = flags.contains(.option)
            let other = !flags.intersection([.command, .control, .shift, .function]).isEmpty
            apply(gesture.flags(option: optionDown, otherModifier: other, overlayVisible: isShowing))
        } else if event.type == .keyDown {
            if !external, handleOverlayShortcut(event) { return true }
            apply(gesture.interrupt())
            if isShowing || event.keyCode == 53 {
                onHide?(event.keyCode == 53 ? .escape : .interruption)
            }
        } else if !isShowing {
            apply(gesture.interrupt())
        } else if external {
            onHide?(.outsideClick)
            apply(gesture.interrupt())
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
    private func apply(_ effect: HoldGesture.Effect) {
        switch effect {
        case .none: break
        case .arm:
            timer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.optionDown, NSEvent.pressedMouseButtons == 0 else { return }
                self.triggered = true
                self.onShow?()
            }
            timer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        case .cancel:
            onCancel?()
            timer?.cancel()
            timer = nil
            if triggered { onHide?(.interruption) }
        case .release:
            timer?.cancel()
            timer = nil
            if triggered { onHide?(.release) }
            triggered = false
            onRelease?()
        }
    }
}
