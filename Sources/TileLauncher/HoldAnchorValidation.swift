import AppKit
import DeckCore

#if TILE_LAUNCHER_DIAGNOSTICS
/// R357: the production HoldMonitor adapter with synthetic flagsChanged/keyDown
/// NSEvents and injected cursor/mouse suppliers. No event monitor, OS input
/// injection, window, settings or app instance is installed. The real 0.25 s
/// timer runs on a bounded main run loop.
enum HoldAnchorValidation {
    @MainActor static func verify() throws {
        let monitor = HoldMonitor()
        var cursor = CGPoint.zero
        var samples = 0, samplesAtReopen = -1
        var prepares: [CGPoint] = [], shows: [CGPoint] = [], reopens: [CGPoint] = []
        var acceptReopen = false
        var time: TimeInterval = 100
        monitor.canTriggerHold = { true }
        monitor.hasPressedMouseButtons = { false }
        monitor.cursorLocation = { samples += 1; return cursor }
        monitor.onPrepare = { prepares.append($0) }
        monitor.onShow = { shows.append($0); monitor.isShowing = true }
        monitor.onHide = { _, _ in monitor.isShowing = false }
        monitor.onQuickReopen = { _, anchor in
            reopens.append(anchor); samplesAtReopen = samples
            return acceptReopen
        }
        defer {
            monitor.stop()
            monitor.onPrepare = nil; monitor.onShow = nil; monitor.onHide = nil; monitor.onQuickReopen = nil
        }
        func check(_ condition: Bool, _ code: Int, _ message: String) throws {
            if !condition {
                throw NSError(domain: "TileLauncher.HoldAnchor", code: code, userInfo: [NSLocalizedDescriptionKey:
                    "\(message): samples=\(samples) prepares=\(prepares) shows=\(shows) reopens=\(reopens)"])
            }
        }
        func send(_ type: NSEvent.EventType, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16) throws {
            time += 0.01
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: time,
                                               windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                               isARepeat: false, keyCode: keyCode) else { try check(false, 1, "Synthetic event"); return }
            _ = monitor.handle(event, external: true)
        }
        func option(_ down: Bool, keyCode: UInt16 = 58) throws { try send(.flagsChanged, down ? .option : [], keyCode: keyCode) }
        func runPastTimer() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
        func reset(at point: CGPoint) {
            cursor = point; samples = 0; samplesAtReopen = -1
            prepares = []; shows = []; reopens = []
        }
        let a = CGPoint(x: 120, y: 840), b = CGPoint(x: -1500, y: 60), c = CGPoint(x: 900, y: 400)

        // Moving during the wait does not move prepare/show; quick reopen sees the
        // same point first and, when declined, the fallback uses it too.
        reset(at: a)
        try option(true)
        cursor = b
        runPastTimer()
        try check(samples == 1 && samplesAtReopen == 1 && reopens == [a] && prepares == [a] && shows == [a],
                  2, "Cursor movement during the hold changed the anchor")
        try option(false)

        // A new press after release samples again.
        reset(at: c)
        try option(true)
        cursor = a
        runPastTimer()
        try check(samples == 1 && prepares == [c] && shows == [c], 3, "Release did not start a new anchor")
        try option(false)

        // Repeated flags and the other Option key keep the first sample.
        reset(at: b)
        try option(true)
        cursor = c
        try option(true, keyCode: 61)
        try option(true, keyCode: 58)
        runPastTimer()
        try check(samples == 1 && prepares == [b] && shows == [b], 4, "Duplicate Option flags resampled the anchor")
        try option(false)

        // Interruption and stop before the timer leave no late prepare/show.
        reset(at: a)
        try option(true)
        try send(.keyDown, [], keyCode: 0)
        cursor = b
        runPastTimer()
        try check(samples == 1 && prepares.isEmpty && shows.isEmpty, 5, "Cancelled gesture delivered late work")
        try option(false)
        reset(at: a)
        try option(true)
        monitor.stop()
        cursor = b
        runPastTimer()
        try check(samples == 1 && prepares.isEmpty && shows.isEmpty, 6, "Stopped gesture delivered late work")
        try option(false)

        // Rapid release/re-press: only the second gesture's anchor is delivered.
        reset(at: a)
        try option(true)
        try option(false)
        cursor = c
        try option(true)
        cursor = b
        runPastTimer()
        try check(samples == 2 && prepares == [c] && shows == [c], 7, "Re-press delivered the previous gesture's anchor")
        try option(false)

        // An accepted quick reopen restores instead; no delayed prepare/show follows.
        acceptReopen = true
        reset(at: c)
        try option(true)
        cursor = a
        runPastTimer()
        try check(samples == 1 && reopens == [c] && prepares.isEmpty && shows.isEmpty, 8,
                  "Accepted quick reopen also scheduled a fresh overlay")
        try option(false)
        acceptReopen = false

        // No sample when the hold cannot trigger or an overlay is already visible.
        monitor.canTriggerHold = { false }
        reset(at: a)
        try option(true)
        runPastTimer()
        try check(samples == 0 && reopens.isEmpty && prepares.isEmpty && shows.isEmpty, 9, "Disabled hold sampled the cursor")
        try option(false)
        monitor.canTriggerHold = { true }
        reset(at: a)
        monitor.isShowing = true
        try option(true)
        runPastTimer()
        try check(samples == 0 && prepares.isEmpty && shows.isEmpty, 10, "Visible overlay press sampled the cursor")
        try option(false)
        monitor.isShowing = false

        print("HoldMonitor anchor: one detection-time sample per valid press reaches quick reopen, prepare and show; movement, duplicate/both Option flags, cancel, stop, re-press, accepted quick reopen, disabled hold and visible overlay passed.")
    }
}
#endif
