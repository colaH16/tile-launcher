import AppKit
import ApplicationServices
import DeckCore

/// Cancellation shared between the observation queue and the resolver.
final class MenuHelpResolutionCancel {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// The single owner of the deferred Help ticket (`MenuDeferredCapture`), locked
/// so the observation queue and the main thread share one policy. The queue
/// issues/checks tickets; any thread may invalidate (stop, settings/target
/// change, suppression, a new menu interaction); the main-thread save performs
/// the final `take` — expiry and exactly-once — immediately before saving.
final class MenuHelpCaptureLedger {
    private let lock = NSLock()
    private var policy = MenuDeferredCapture()
    func confirm(generation: UInt64, at time: TimeInterval, duration: TimeInterval) -> MenuDeferredCapture.Ticket? {
        lock.lock(); defer { lock.unlock() }
        return policy.confirm(generation: generation, at: time, duration: duration)
    }
    func isCurrent(_ ticket: MenuDeferredCapture.Ticket, generation: UInt64, at time: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return policy.isCurrent(ticket, generation: generation, at: time)
    }
    /// A normal menu close keeps a released selection.
    func menuClosed() { lock.lock(); policy.menuClosed(); lock.unlock() }
    func invalidate() { lock.lock(); policy.cancel(); lock.unlock() }
    /// The final transaction: `checks` (current settings, frontmost process,
    /// cancellation) run first without the lock; `take` is last, so anything
    /// invalidated meanwhile, expired, superseded or already saved is rejected.
    func finalize(_ ticket: MenuDeferredCapture.Ticket,
                  clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, checks: () -> Bool) -> Bool {
        guard checks() else { return false }
        lock.lock(); defer { lock.unlock() }
        // Lifecycle/generation changes reach here only as invalidation.
        // Sample after potentially slow process checks and lock acquisition.
        return policy.take(ticket, generation: ticket.generation, at: clock())
    }
}

/// A Help result physically chosen by a release on its saved row. Only the
/// row's label is kept; the real menu is resolved later from a complete read.
struct MenuHelpDeferredRequest {
    let ticket: MenuDeferredCapture.Ticket
    let label: String
    let app: AppItem
    let process: ProcessIdentity
    let bar: AXUIElement
    /// Release event time: suppression is compared at the user's action time.
    let eventTime: TimeInterval
    let cancel = MenuHelpResolutionCancel()
    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    let diagnosticContext: MenuCaptureDiagnostics.Context
    let diagnosticOrigin: MenuCaptureDiagnostics.Stamp?
    /// Per-process; `logActive` also enables the catalog's read-free context tracking.
    let structureGate: MenuHelpStructureProbeGate
    /// `structureGate.captureEpoch()` at seal; a later diagnostic cancellation
    /// (target/settings change, stop, suppression) makes this request's probe ineligible.
    let structureEpoch: UInt64
    #endif
    var id: UInt64 { ticket.id }
    var generation: UInt64 { ticket.generation }
    var sealedAt: TimeInterval { ticket.confirmedAt }
    var deadline: TimeInterval { ticket.expiresAt }
}

enum MenuHelpResolutionFailure {
    case traversal(MenuCatalogTraversal.Failure)
    case process, identifier, cancelled, deadline
}

struct MenuHelpTraversalStats {
    var nodes = 0
    var depth = 0
    var children = 0
    var leaves = 0
    var matched = 0
    var identities = 0
    var duration: TimeInterval = 0
    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    /// First non-success AXChildren read, kept even if the traversal then
    /// classifies the stop as deadline/cancel. Diagnostics only; no decision uses it.
    var childrenTrace: MenuHelpChildrenRead.Trace? = nil
    /// R374: first non-accepted AXRole read and where it sat (read-free context).
    var roleTrace: MenuHelpRoleRead.Trace? = nil
    var roleContext: MenuHelpRoleRead.Context? = nil
    /// R374: bounded structure probe after a role failure (both flags only).
    var structure: MenuHelpStructureProbe.Report? = nil
    #endif
}

enum MenuHelpResolutionOutcome {
    case resolved(CapturedMenu, MenuHelpTraversalStats)
    /// The list was complete, but the label matched no single identity.
    case unresolved(MenuHelpTraversalStats)
    case failed(MenuHelpResolutionFailure, MenuHelpTraversalStats)
}

/// Serial, one operation at a time. The monitor allows one in flight and keeps
/// only the latest pending request; there are no retries.
final class MenuHelpDeferredResolver {
    private let queue = DispatchQueue(label: "TileLauncher.menu-help-resolver", qos: .utility)
    func resolve(_ request: MenuHelpDeferredRequest, deliverOn target: DispatchQueue,
                 completion: @escaping (MenuHelpResolutionOutcome) -> Void) {
        queue.async {
            let outcome = MenuHelpCatalogRead(request: request).resolve()
            target.async { completion(outcome) }
        }
    }
}

enum MenuHelpChildrenPolicy {
    /// AXChildren is required for objects containing accessible children. Only
    /// explicit attributeUnsupported on a known menu item means an exposed leaf;
    /// noValue and messaging errors do not establish an empty subtree.
    /// https://developer.apple.com/documentation/applicationservices/kaxchildrenattribute
    static func isUnsupportedLeaf(_ error: AXError, menuItem: Bool) -> Bool {
        menuItem && error == .attributeUnsupported
    }
}

/// Native adapter for `MenuCatalogTraversal`: structure and titles of the whole
/// current menu bar (except Apple/Help), then identifier/shortcut only for the
/// leaves whose path matches the label. Never reads window/document content,
/// search text or performs actions. Every AX call has a 25 ms messaging timeout
/// and the request's absolute deadline/cancellation is checked between reads.
private final class MenuHelpCatalogRead {
    private static let limits = MenuCatalogTraversal.Limits(nodes: 3000, children: 100, depth: 12)
    private let request: MenuHelpDeferredRequest
    private var stats = MenuHelpTraversalStats()
    private let started = ProcessInfo.processInfo.systemUptime
    /// `scan` reads role, then title/children of the same node; this remembers
    /// the role so a missing AXChildren is accepted as a leaf only for a menu item.
    private var lastRole: (node: AXUIElement, role: MenuCatalogTraversal.Role)?
    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    // R374 read-free context: the DFS path of children lists the catalog already
    // read, so a role failure gets its parent role, depth, root and sibling
    // references without AXParent or any other query. Only with an active log.
    private var tracking: Bool { request.structureGate.logActive }
    private struct RoleFailure {
        let node: AXUIElement
        let trace: MenuHelpRoleRead.Trace
        let context: MenuHelpRoleRead.Context
        /// Other children of the same parent; nil for menu bar roots or unknown.
        let siblings: [AXUIElement]?
    }
    private var roleFailure: RoleFailure?
    private var catalogPath = MenuHelpCatalogPath<AXUIElement>(equal: { CFEqual($0, $1) })
    /// (B), only through the gate. Runs while the request is still tracked by the
    /// monitor, so a new capture cancels `request.cancel`; target/settings change,
    /// stop, suppression and an unavailable log cancel through the gate.
    private func structureProbe(after failure: MenuCatalogTraversal.Failure) -> MenuHelpStructureProbe.Report? {
        guard let failed = roleFailure, let targetRole = failed.trace.role else { return nil }
        let request = self.request
        return request.structureGate.run(expectedEpoch: request.structureEpoch, after: failed.trace,
                                         catalogFailure: failure, canStart: {
            !request.cancel.isCancelled && ProcessInfo.processInfo.systemUptime < request.deadline
        }) { gateCancelled in
            let deadline = min(ProcessInfo.processInfo.systemUptime + MenuHelpStructureProbe.Limits().seconds,
                               request.deadline)
            let cancelled = { request.cancel.isCancelled || gateCancelled() }
            let proceed = { !cancelled() && ProcessInfo.processInfo.systemUptime < deadline }
            return MenuHelpStructureProbe.scan(
                target: failed.node, targetRole: targetRole, siblings: failed.siblings,
                role: { node in
                    AXUIElementSetMessagingTimeout(node, 0.025)
                    var value: CFTypeRef?
                    let error = AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &value)
                    return (error, value)
                },
                children: { node, limit in
                    AXUIElementSetMessagingTimeout(node, 0.025)
                    return MenuHelpStructureChildrenRead.read(limit: limit, count: {
                        var count: CFIndex = 0
                        let result = AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count)
                        return (result, count)
                    }, canCopy: proceed, copy: { requested in
                        var values: CFArray?
                        let result = AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, requested, &values)
                        return (result, values)
                    })
                },
                clock: { ProcessInfo.processInfo.systemUptime }, deadline: deadline,
                isCancelled: cancelled)
        }
    }
    #endif

    init(request: MenuHelpDeferredRequest) { self.request = request }

    private var hasTime: Bool { ProcessInfo.processInfo.systemUptime < request.deadline }
    private var stopped: MenuHelpResolutionFailure? {
        if request.cancel.isCancelled { return .cancelled }
        if !hasTime { return .deadline }
        return nil
    }

    func resolve() -> MenuHelpResolutionOutcome {
        if let stopped { return .failed(stopped, finished()) }
        // Process start-time identity, not just the PID, so a reused PID never matches.
        guard processMatches() else { return .failed(.process, finished()) }
        let outcome = MenuCatalogTraversal.scan(roots: { self.roots() }, role: { self.role($0) },
                                                title: { self.title($0) }, children: { self.children($0) },
                                                hasTime: { self.hasTime }, isCancelled: { self.request.cancel.isCancelled },
                                                limits: Self.limits)
        let entries: [MenuCatalogTraversal.Entry<AXUIElement>]
        switch outcome {
        case .incomplete(let failure, let statistics):
            note(statistics)
            // The scan duration is fixed here; a diagnostic probe is timed separately
            // and never changes this already failed (fail-closed) outcome.
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            var failed = finished()
            failed.roleTrace = roleFailure?.trace
            failed.roleContext = roleFailure?.context
            failed.structure = structureProbe(after: failure)
            return .failed(.traversal(failure), failed)
            #else
            return .failed(.traversal(failure), finished())
            #endif
        case .complete(let list, let statistics):
            note(statistics)
            entries = list
        }
        stats.leaves = entries.count
        let appID = request.app.id, appName = request.app.name
        // resolveHelp's own exact/breadcrumb predicate, applied per path.
        let matched = entries.filter {
            MenuCapturePolicy.resolveHelp(title: request.label,
                                          choices: [CapturedMenu(appID: appID, appName: appName, path: $0.path)]) != nil
        }
        stats.matched = matched.count
        stats.identities = Set(matched.map(\.path)).count
        // More than one identity (including a literal-vs-breadcrumb collision)
        // is ambiguous in resolveHelp regardless of any metadata.
        guard stats.identities == 1 else {
            if let stopped { return .failed(stopped, finished()) }
            return .unresolved(finished())
        }
        // Every member of the one identity gets its identifier read; resolveHelp
        // below still rejects any identifier conflict.
        var identifiers: [String?] = []
        for entry in matched {
            if let stopped { return .failed(stopped, finished()) }
            guard case .read(let identifier) = readIdentifier(entry.node) else { return .failed(.identifier, finished()) }
            identifiers.append(identifier)
        }
        // The shortcut is read once, for the representative resolveHelp returns (the first).
        if let stopped { return .failed(stopped, finished()) }
        AXUIElementSetMessagingTimeout(matched[0].node, 0.025)
        let reading = MenuShortcutReading.read(matched[0].node)
        let modifiers = reading.shortcut?.modifiers ?? 0
        let choices = zip(matched, identifiers).enumerated().map { index, pair in
            index == 0
                ? CapturedMenu(appID: appID, appName: appName, path: pair.0.path, shortcut: reading.shortcut?.key ?? "",
                               commandModifier: modifiers & (1 << 3) == 0, modifiers: modifiers,
                               shortcutKnown: reading.known, axIdentifier: pair.1)
                : CapturedMenu(appID: appID, appName: appName, path: pair.0.path, axIdentifier: pair.1)
        }
        if let stopped { return .failed(stopped, finished()) }
        guard processMatches() else { return .failed(.process, finished()) }
        let resolution = MenuCapturePolicy.resolveHelp(title: request.label, choices: choices)
        // The whole operation, including local work, stays within the deadline.
        if let stopped { return .failed(stopped, finished()) }
        guard let menu = resolution else { return .unresolved(finished()) }
        return .resolved(menu, finished())
    }
    private func note(_ statistics: MenuCatalogTraversal.Statistics) {
        stats.nodes = statistics.nodes
        stats.depth = statistics.maximumDepth
        stats.children = statistics.maximumChildren
    }
    private func finished() -> MenuHelpTraversalStats {
        var result = stats
        result.duration = ProcessInfo.processInfo.systemUptime - started
        return result
    }
    private func processMatches() -> Bool {
        ProcessIdentity.read(pid: request.app.pid) == request.process
    }

    // MARK: AX reads

    private enum Copy { case value(CFTypeRef?), unavailable, failure }
    private func copy(_ node: AXUIElement, _ key: String) -> Copy {
        AXUIElementSetMessagingTimeout(node, 0.025)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(node, key as CFString, &value)
        if error == .success { return .value(value) }
        return error == .attributeUnsupported || error == .noValue ? .unavailable : .failure
    }
    private func elements(_ node: AXUIElement, leafAllowed: Bool) -> MenuCatalogTraversal.Read<[AXUIElement]> {
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        // Same AX calls, timeout, order and decisions as the #else body; only
        // the first failing branch is recorded (no extra query, no log line).
        AXUIElementSetMessagingTimeout(node, 0.025)
        return MenuHelpChildrenRead.read(
            leafAllowed: leafAllowed, limit: Self.limits.children,
            count: {
                var count: CFIndex = 0
                let result = AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count)
                return (result, count)
            },
            canCopy: { self.hasTime && !self.request.cancel.isCancelled },
            copy: { requested in
                var values: CFArray?
                let result = AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, requested, &values)
                return (result, values)
            },
            report: { trace in if self.stats.childrenTrace == nil { self.stats.childrenTrace = trace } })
        #else
        AXUIElementSetMessagingTimeout(node, 0.025)
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count)
        if result == .attributeUnsupported || result == .noValue {
            return MenuHelpChildrenPolicy.isUnsupportedLeaf(result, menuItem: leafAllowed) ? .value([]) : .unavailable
        }
        guard result == .success, count >= 0 else { return .failure }
        if count == 0 { return .value([]) }
        guard hasTime, !request.cancel.isCancelled else { return .failure }
        // Beyond the cap, fetch only cap + 1 so the traversal reports childLimit
        // honestly without retrieving an oversized list.
        let requested = min(count, Self.limits.children + 1)
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, requested, &values) == .success,
              let items = values as? [AnyObject], items.count == requested else { return .failure }
        var children: [AXUIElement] = []
        children.reserveCapacity(items.count)
        for item in items {
            // Every element must really be an AX element; anything else is incomplete.
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else { return .failure }
            children.append(item as! AXUIElement)
        }
        return .value(children)
        #endif
    }
    private func roots() -> MenuCatalogTraversal.Read<[MenuCatalogTraversal.Root<AXUIElement>]> {
        switch elements(request.bar, leafAllowed: false) {
        case .value(let nodes):
            #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
            if tracking { catalogPath.didReadRoots(nodes) }
            #endif
            // The system Apple menu is the menu bar's first child, as in menuPath.
            return .value(nodes.enumerated().map { .init(node: $0.element, isAppleMenu: $0.offset == 0) })
        case .unavailable: return .unavailable
        case .failure: return .failure
        }
    }
    private func role(_ node: AXUIElement) -> MenuCatalogTraversal.Read<MenuCatalogTraversal.Role> {
        lastRole = nil
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        // Same single AXRole copy, timeout and decision as the #else body.
        let result = MenuHelpRoleRead.read({
            AXUIElementSetMessagingTimeout(node, 0.025)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &value)
            return (error, value)
        }, report: { trace in
            guard roleFailure == nil else { return }
            // Sibling references only below a menu bar item (nil at the root level).
            let located = tracking ? catalogPath.locate(node) : nil
            roleFailure = RoleFailure(node: node, trace: trace, context: located?.context ?? .unknown,
                                      siblings: located?.siblings)
        })
        if case .value(let accepted) = result { lastRole = (node, accepted) }
        return result
        #else
        // The shared production mapping: one AXRole copy, five accepted roles;
        // custom item content and other roles fail closed.
        let result = MenuHelpCatalogRoleRead.read {
            AXUIElementSetMessagingTimeout(node, 0.025)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &value)
            return (error, value)
        }
        if case .value(let accepted) = result { lastRole = (node, accepted) }
        return result
        #endif
    }
    private func title(_ node: AXUIElement) -> MenuCatalogTraversal.Read<String> {
        switch copy(node, kAXTitleAttribute) {
        case .value(let value):
            guard let string = value as? String else { return .failure }
            return .value(string)
        case .unavailable: return .unavailable
        case .failure: return .failure
        }
    }
    private func children(_ node: AXUIElement) -> MenuCatalogTraversal.Read<[AXUIElement]> {
        // Only a known menu item may be a leaf by an unsupported AXChildren;
        // groups and controls always need an explicitly read list.
        let menuItem = lastRole.map { CFEqual($0.node, node) && $0.role == .menuItem } == true
        #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
        let result = elements(node, leafAllowed: menuItem)
        // Bookkeeping of references already returned; no additional AX call.
        if tracking, case .value(let kids) = result {
            catalogPath.didReadChildren(of: node, role: lastRole.flatMap { CFEqual($0.node, node) ? $0.role : nil },
                                        children: kids)
        }
        return result
        #else
        return elements(node, leafAllowed: menuItem)
        #endif
    }
    private enum Identifier { case read(String?), failure }
    /// Only unsupported/noValue means "no identifier". A failed read, or a
    /// success without a string value, could hide a conflict and fails closed.
    private func readIdentifier(_ node: AXUIElement) -> Identifier {
        switch copy(node, kAXIdentifierAttribute) {
        case .value(let value):
            guard let string = value as? String else { return .failure }
            return .read(string)
        case .unavailable: return .read(nil)
        case .failure: return .failure
        }
    }
}
