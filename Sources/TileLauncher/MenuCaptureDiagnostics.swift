#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import AppKit
import Darwin
import DeckCore
import Foundation

/// Temporary, explicitly opted-in metadata only. No API accepts menu/user text,
/// AX values, coordinates, keys, app IDs or arbitrary diagnostic messages.
final class MenuCaptureDiagnostics {
    enum Stage: String, Encodable {
        case started, input, menuState, hit, helpRow, catalog, resolution, gate, record, deferred
    }
    enum Outcome: String, Encodable {
        case observed, accepted, absent, staleTarget, noMenuBar, staleInput, noPoint
        case unrelated, unsupportedHit, appleMenu, noCandidate, opened, closed, reset
        case rowAccepted, rowRejected, cacheHit, complete, incomplete, resolved, unresolved
        case suppressed, unarmed, consumed, beforeArm, expired, unmatched, policyRejected
        case queued, recorded, settingsRejected
        // Deferred Help click lifecycle.
        case rowHeld, releasedOutside, sealed, started, cancelled, lifecycleChanged, staleCompletion
    }
    /// Why a deferred Help resolution read stopped before a complete list.
    enum DeferredFailure: String, Encodable {
        case invalidLimits, cancelled, deadline, nodeLimit, depthLimit, childLimit
        case rootsUnavailable, roleUnavailable, titleUnavailable, childrenUnavailable
        case rootsReadFailure, roleReadFailure, titleReadFailure, childrenReadFailure
        case invalidRootRole, unnamedBranch, process, identifier
    }
    enum CancelReason: String, Encodable { case superseded, newInteraction, cancelKey, lifecycle, suppressed, expired }
    enum Input: String, Encodable { case none, mouseDown, mouseUp, confirm, cancel, navigation }
    enum Role: String, Encodable { case unknown, menuItem, menuBarItem, menu, row, cell, staticText, image, other }
    struct Context: Encodable, Equatable {
        var generation: UInt64 = 0
        var helpSession: UInt64 = 0
    }
    struct Stamp: Encodable {
        let sequence: UInt64
        let context: Context
    }
    struct Values: Encodable {
        var input: Input? = nil
        var role: Role? = nil
        var ageMilliseconds: Int? = nil
        var durationMilliseconds: Int? = nil
        var count: Int? = nil
        var nodeCount: Int? = nil
        var childCount: Int? = nil
        var depth: Int? = nil
        var candidateCount: Int? = nil
        var identityCount: Int? = nil
        var identifierCount: Int? = nil
        var cellCount: Int? = nil
        var labelCount: Int? = nil
        var rowFailure: MenuHelpSearchRow.Diagnostic.Failure? = nil
        var budgetExceeded: Bool? = nil
        var ipcFailures: Int? = nil
        var missingValues: Int? = nil
        var childLimit: Bool? = nil
        var nodeLimit: Bool? = nil
        var depthLimit: Bool? = nil
        var generationChanged: Bool? = nil
        var helpSessionChanged: Bool? = nil
        var menuActive: Bool? = nil
        var helpActive: Bool? = nil
        var cachePresent: Bool? = nil
        var catalogComplete: Bool? = nil
        var hadDown: Bool? = nil
        var hadHighlight: Bool? = nil
        var frameContains: Bool? = nil
        var freshHit: Bool? = nil
        var requestID: UInt64? = nil
        var deferredFailure: DeferredFailure? = nil
        var cancelReason: CancelReason? = nil
        var leafCount: Int? = nil
        var matchedCount: Int? = nil
        // First non-success AXChildren read of a deferred Help traversal (R368).
        var childrenFailure: MenuHelpChildrenRead.Failure? = nil
        var childrenCountError: Int? = nil
        var childrenCopyError: Int? = nil
        var childrenReportedCount: Int? = nil
        var childrenRequestedCount: Int? = nil
        var childrenReturnedCount: Int? = nil
        var childrenInvalidIndex: Int? = nil
        // First non-accepted AXRole read of a deferred Help traversal (R374 A).
        var roleFailure: MenuHelpRoleRead.Failure? = nil
        var roleErrorCode: Int? = nil
        var roleValueType: MenuHelpRoleRead.ValueType? = nil
        var roleCategory: MenuHelpRoleRead.KnownRole? = nil
        var roleContext: MenuHelpRoleRead.Context? = nil
        // Bounded structure metadata (R374 B; --menu-capture-structure only).
        var structure: MenuHelpStructureProbe.Report? = nil
    }
    private struct Line: Encodable {
        let schema = 1
        let ordinal: Int
        let elapsedMilliseconds: Int
        let stage: Stage
        let outcome: Outcome
        let context: Context
        let origin: Stamp?
        let values: Values
    }
    struct Limits {
        var seconds: TimeInterval = 600
        var bytes = 1_048_576
        var records = 200
        var pending = 32
    }

    let fileURL: URL
    private let descriptor: Int32
    private let writer: DispatchQueue
    private let slots: DispatchSemaphore
    private let writes = DispatchGroup()
    private let lock = NSLock()
    private let clock: () -> TimeInterval
    private let started: TimeInterval
    private let limits: Limits
    private var context = Context()
    private var inputSequence: UInt64 = 0
    private var reserved = 0
    private var closed = false
    // Lock-protected mirrors for `canAcceptRecords`; the writer only flips them
    // under the lock after its disk I/O, never holding the lock during I/O.
    private var pendingWrites = 0
    private var outputFailed = false
    // Writer-queue owned, never touched by the menu observation queue.
    private var writtenBytes = 0
    private var writeFailed = false
    private var terminationToken: NSObjectProtocol?

    static func makeIfRequested(arguments: [String] = CommandLine.arguments,
                                directory: URL = FileManager.default.temporaryDirectory) -> MenuCaptureDiagnostics? {
        guard arguments.contains("--menu-capture-log") else { return nil }
        return MenuCaptureDiagnostics(directory: directory)
    }

    /// Internal injection is only for the synthetic validator; production uses
    /// fixed defaults and the system temporary directory through makeIfRequested.
    init?(directory: URL, limits: Limits = .init(),
          clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
          writerQueue: DispatchQueue? = nil) {
        guard limits.seconds > 0, limits.seconds.isFinite, limits.bytes > 0,
              limits.records > 0, limits.pending > 0 else { return nil }
        var template = Array(directory.appendingPathComponent("tile-launcher-menu-capture-XXXXXX").path.utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { return nil }
        guard fchmod(fd, S_IRUSR | S_IWUSR) == 0 else {
            Darwin.close(fd)
            template.withUnsafeBufferPointer { _ = unlink($0.baseAddress!) }
            return nil
        }
        descriptor = fd
        fileURL = URL(fileURLWithPath: template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
        self.limits = limits
        self.clock = clock
        started = clock()
        writer = writerQueue ?? DispatchQueue(label: "TileLauncher.menu-diagnostic-writer", qos: .utility)
        slots = DispatchSemaphore(value: limits.pending)
        terminationToken = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                  object: nil, queue: nil) { [weak self] _ in
            // Normal termination flushes a bounded queue; crashes/force-kill do
            // not claim delivery. No file I/O occurs on the observation queue.
            _ = self?.finish(timeout: 1)
        }
        _ = record(.started, .observed)
    }

    deinit {
        if let terminationToken { NotificationCenter.default.removeObserver(terminationToken) }
        Darwin.close(descriptor)
    }

    func updateContext(_ value: Context) {
        lock.lock(); context = value; lock.unlock()
    }
    func stamp() -> Stamp {
        lock.lock(); defer { lock.unlock() }
        inputSequence &+= 1
        return Stamp(sequence: inputSequence, context: context)
    }
    static func milliseconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite else { return 0 }
        return Int(max(-600_000, min(600_000, (interval * 1_000).rounded())))
    }

    /// Enqueueing is non-blocking when full. Its arguments cannot carry text.
    @discardableResult
    func record(_ stage: Stage, _ outcome: Outcome, context suppliedContext: Context? = nil,
                origin: Stamp? = nil, values: Values = .init()) -> Bool {
        guard slots.wait(timeout: .now()) == .success else { return false }
        let now = clock()
        lock.lock()
        guard !closed, now >= started, now - started <= limits.seconds,
              reserved < limits.records else {
            lock.unlock(); slots.signal(); return false
        }
        reserved += 1
        pendingWrites += 1
        let line = Line(ordinal: reserved, elapsedMilliseconds: Self.milliseconds(now - started),
                        stage: stage, outcome: outcome, context: suppliedContext ?? context,
                        origin: origin, values: values)
        writes.enter()
        writer.async { [self] in
            defer {
                let failed = writeFailed
                lock.lock(); pendingWrites -= 1; if failed { outputFailed = true }; lock.unlock()
                slots.signal(); writes.leave()
            }
            guard !writeFailed, let encoded = try? JSONEncoder().encode(line) else { return }
            var data = encoded
            data.append(0x0a)
            guard writtenBytes <= limits.bytes, data.count <= limits.bytes - writtenBytes else {
                writeFailed = true
                return
            }
            let succeeded = data.withUnsafeBytes { bytes -> Bool in
                guard let base = bytes.baseAddress else { return true }
                var offset = 0
                while offset < bytes.count {
                    let result = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                    if result < 0, errno == EINTR { continue }
                    guard result > 0 else { return false }
                    offset += result
                }
                return true
            }
            if succeeded { writtenBytes += data.count } else { writeFailed = true }
        }
        lock.unlock()
        return true
    }

    /// Best-effort, non-blocking: whether another record could still be accepted
    /// now (open, within the time window, below the record cap, with a free
    /// pending slot, and no write failure/byte-budget exhaustion seen yet). A race
    /// with a concurrent record/write is possible; it only gates optional work.
    func canAcceptRecords() -> Bool {
        let now = clock()
        lock.lock(); defer { lock.unlock() }
        return !closed && !outputFailed && now >= started && now - started <= limits.seconds
            && reserved < limits.records && pendingWrites < limits.pending
    }

    /// Called from normal termination or the validator, never the menu queue.
    /// Prevents new entries and waits at most timeout for already accepted writes.
    @discardableResult
    func finish(timeout: TimeInterval = 1) -> Bool {
        lock.lock(); closed = true; lock.unlock()
        return writes.wait(timeout: .now() + max(0, min(timeout, 1))) == .success
    }
}
#endif
