#if TILE_LAUNCHER_DIAGNOSTICS || TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import DeckCore
import Foundation
import ApplicationServices

/// R364: the cross-queue pieces the monitor actually uses for a deferred Help
/// click — the locked ticket ledger (final save transaction) and the shared
/// cancellation flag. Injected times and private queues only; no AX, app,
/// window, event monitor or production instance.
enum MenuHelpDeferredValidation {
    static func run() throws {
        func check(_ condition: Bool, _ code: Int, _ message: String) throws {
            if !condition {
                throw NSError(domain: "TileLauncher.MenuHelpDeferred", code: code,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let generation: UInt64 = 7
        let accept: () -> Bool = { true }

        try check(MenuHelpChildrenPolicy.isUnsupportedLeaf(.attributeUnsupported, menuItem: true), 26,
                  "Explicit unsupported AXChildren on a menu item must retain standard leaf compatibility")
        try check(!MenuHelpChildrenPolicy.isUnsupportedLeaf(.attributeUnsupported, menuItem: false), 27,
                  "A container with unavailable children must not become a leaf")
        try check(!MenuHelpChildrenPolicy.isUnsupportedLeaf(.noValue, menuItem: true)
                  && !MenuHelpChildrenPolicy.isUnsupportedLeaf(.cannotComplete, menuItem: true), 28,
                  "Missing or failed child reads must not become leaves")

        // Normal flow: issue, stay current through a normal menu close, save once.
        var ledger = MenuHelpCaptureLedger()
        guard let first = ledger.confirm(generation: generation, at: 100, duration: 2) else {
            try check(false, 1, "Ticket not issued"); return
        }
        ledger.menuClosed()
        try check(ledger.isCurrent(first, generation: generation, at: 100.5), 2, "Normal close invalidated a released selection")
        try check(ledger.finalize(first, clock: { 101 }, checks: accept), 3, "Current ticket was not saved")
        try check(!ledger.finalize(first, clock: { 101.1 }, checks: accept), 4, "Duplicate completion saved twice")

        // A delayed main-thread save after the absolute expiry is rejected.
        ledger = MenuHelpCaptureLedger()
        guard let late = ledger.confirm(generation: generation, at: 200, duration: 2) else {
            try check(false, 5, "Ticket not issued"); return
        }
        try check(ledger.isCurrent(late, generation: generation, at: 201.9), 6, "Ticket expired early")
        try check(!ledger.finalize(late, clock: { 202.01 }, checks: accept), 7, "Save after expiry was accepted")

        // Process validation itself may cross the deadline. Sample time only
        // after those checks, immediately before the locked policy take.
        ledger = MenuHelpCaptureLedger()
        guard let crossing = ledger.confirm(generation: generation, at: 250, duration: 2) else {
            try check(false, 24, "Ticket not issued"); return
        }
        var finalTime: TimeInterval = 251.9
        try check(!ledger.finalize(crossing, clock: { finalTime }, checks: {
            finalTime = 252.01
            return true
        }), 25, "Time spent in final checks bypassed expiry")

        // A newer selection supersedes; the older completion cannot consume it.
        ledger = MenuHelpCaptureLedger()
        guard let older = ledger.confirm(generation: generation, at: 300, duration: 2),
              let newer = ledger.confirm(generation: generation, at: 300.2, duration: 2) else {
            try check(false, 8, "Ticket not issued"); return
        }
        try check(newer.id > older.id, 9, "Ticket IDs are not monotonic")
        try check(!ledger.finalize(older, clock: { 300.3 }, checks: accept), 10, "Superseded completion was saved")
        try check(ledger.finalize(newer, clock: { 300.4 }, checks: accept), 11, "Older completion consumed the newer ticket")

        // New menu input, stop, settings/target change and suppression all use
        // invalidate(), from the observation queue or the main thread.
        let observation = DispatchQueue(label: "TileLauncher.validation.observation")
        for (index, invalidateOnQueue) in [true, false].enumerated() {
            ledger = MenuHelpCaptureLedger()
            guard let ticket = ledger.confirm(generation: generation, at: 400, duration: 2) else {
                try check(false, 12, "Ticket not issued"); return
            }
            if invalidateOnQueue { observation.sync { ledger.invalidate() } } else { ledger.invalidate() }
            try check(!ledger.isCurrent(ticket, generation: generation, at: 400.1)
                      && !ledger.finalize(ticket, clock: { 400.1 }, checks: accept), 13 + index, "Invalidated ticket was saved")
        }

        // A failed main-thread check (settings, frontmost process, cancellation)
        // declines without consuming; the take itself is the last step.
        ledger = MenuHelpCaptureLedger()
        guard let checked = ledger.confirm(generation: generation, at: 500, duration: 2) else {
            try check(false, 15, "Ticket not issued"); return
        }
        var checksRan = 0
        try check(!ledger.finalize(checked, clock: { 500.1 }, checks: { checksRan += 1; return false }), 16, "Failed check saved")
        try check(checksRan == 1 && ledger.isCurrent(checked, generation: generation, at: 500.2), 17,
                  "A failed check consumed or skipped the ticket")
        // Invalidation that lands while the checks run still prevents the save.
        try check(!ledger.finalize(checked, clock: { 500.3 }, checks: { ledger.invalidate(); return true }), 18,
                  "Invalidation during the final checks did not prevent the save")
        try check(!ledger.isCurrent(checked, generation: generation, at: 500.4), 19, "Ticket survived invalidation during checks")

        // Shared cancellation is visible across queues (resolver checks it between reads).
        let cancel = MenuHelpResolutionCancel()
        try check(!cancel.isCancelled, 20, "New request starts cancelled")
        let resolver = DispatchQueue(label: "TileLauncher.validation.resolver")
        observation.sync { cancel.cancel() }
        try check(resolver.sync { cancel.isCancelled }, 21, "Cancellation not visible to the resolver queue")

        // Contended invalidation/confirmation from two queues leaves at most one save.
        let shared = MenuHelpCaptureLedger()
        guard let contended = shared.confirm(generation: generation, at: 600, duration: 2) else {
            try check(false, 22, "Ticket not issued"); return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var saves = 0
        for _ in 0..<8 {
            DispatchQueue.global().async(group: group) {
                if shared.finalize(contended, clock: { 600.5 }, checks: { true }) { lock.lock(); saves += 1; lock.unlock() }
            }
        }
        group.wait()
        try check(saves == 1, 23, "Concurrent completions saved \(saves) times")

        print("Menu Help deferred: ticket issue/normal close/once, delayed expiry, supersede, queue/main invalidation, failed final checks, cancellation and concurrent completion passed without AX.")
    }
}
#endif
