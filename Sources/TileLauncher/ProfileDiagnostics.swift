#if TILE_LAUNCHER_PROFILE_DIAGNOSTICS
import AppKit
import Darwin
import DeckCore
import Foundation

/// R386 opt-in Focus/profile diagnostics (diagnostic builds only). Typed values
/// only: Bool, enums and counters. No profile IDs, names, hashes, app/pin
/// lists, paths or error descriptions are ever serialized or printed.
enum ProfileDiagnostics {
    enum Event: String, Encodable {
        case started, stopped
        case focusPerform, focusNotification
        case queryStarted, queryCompleted
        case observerRequested, observerCompleted, observerTimeout
        case invocation
        /// Existing `ProfileQuery.entities(for:)` resolution (counts only).
        case entityQueryStarted, entityQueryCompleted
    }
    /// Existing product `.current` query callers.
    enum Source: String, Encodable { case appLaunch, wake, autoSelect }
    /// Diagnostic-only observer reads (never assigned to product state).
    enum Purpose: String, Encodable { case recordingStart, show }
    enum Outcome: String, Encodable { case profile, noProfile, error }
    enum Invocation: String, Encodable { case show, hide, present, manualSelection, followFocusSelection, temporaryCycle }
    /// Mirrors the existing `SettingsStore.activeProfile` priority; it does not replace it.
    enum Reason: String, Encodable { case focus, manual, firstFallback }

    struct Snapshot: Encodable, Equatable {
        var followFocus: Bool
        var focusIDPresent: Bool
        var focusMember: Bool
        var manualMember: Bool
        var reason: Reason
        /// The actual `activeProfile` equals the profile `reason` implies.
        var activeMatchesReason: Bool
        var profileCount: Int
        var panelVisible: Bool
        var presentationProfilePresent: Bool
        /// nil without a presentation profile.
        var presentationMatchesActive: Bool?

        /// Pure form for fixtures; IDs are compared in memory only.
        static func make(profileIDs: [String], followFocus: Bool, focusProfileID: String?, manualProfileID: String,
                         activeProfileID: String, presentationProfileID: String?, panelVisible: Bool) -> Snapshot {
            let ids = Set(profileIDs)
            let focusMember = focusProfileID.map(ids.contains) ?? false
            let manualMember = ids.contains(manualProfileID)
            let reason: Reason = followFocus && focusMember ? .focus : manualMember ? .manual : .firstFallback
            let implied = reason == .focus ? focusProfileID : reason == .manual ? manualProfileID : profileIDs.first
            return Snapshot(followFocus: followFocus, focusIDPresent: focusProfileID != nil, focusMember: focusMember,
                            manualMember: manualMember, reason: reason, activeMatchesReason: implied == activeProfileID,
                            profileCount: profileIDs.count, panelVisible: panelVisible,
                            presentationProfilePresent: presentationProfileID != nil,
                            presentationMatchesActive: presentationProfileID.map { $0 == activeProfileID })
        }
        /// Reads the actual `SettingsStore.activeProfile` once.
        static func make(settings: SettingsStore, presentationProfileID: String?, panelVisible: Bool) -> Snapshot {
            make(profileIDs: settings.profiles.map(\.id), followFocus: settings.followFocus,
                 focusProfileID: settings.focusProfileID, manualProfileID: settings.manualProfileID,
                 activeProfileID: settings.activeProfile.id, presentationProfileID: presentationProfileID,
                 panelVisible: panelVisible)
        }
    }

    struct Values: Encodable {
        var source: Source? = nil
        var purpose: Purpose? = nil
        /// Per-session query/observer ordinal; not an identifier of user data.
        var query: Int? = nil
        var outcome: Outcome? = nil
        var invocation: Invocation? = nil
        var held: Bool? = nil
        var hasProfile: Bool? = nil
        var changed: Bool? = nil
        var returnedPresent: Bool? = nil
        var returnedMember: Bool? = nil
        var returnedMatchesCached: Bool? = nil
        /// Only when a successful query had a later applied notification.
        var returnedMatchesLatestNotification: Bool? = nil
        var notificationSerial: Int? = nil
        /// Focus notifications applied between a query's start and completion.
        var notificationsSinceStart: Int? = nil
        var observerReads: Int? = nil
        var skippedObservations: Int? = nil
        /// Observer completion after its 2 s timeout was already recorded.
        var timedOut: Bool? = nil
        var requestedCount: Int? = nil
        var resolvedCount: Int? = nil
        var snapshot: Snapshot? = nil
    }

    /// In-memory state the recorder reads only while recording.
    struct State {
        let focusProfileID: String?
        let profileIDs: Set<String>
        let snapshot: Snapshot
    }

    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TileLauncher-ProfileDiagnostics", isDirectory: true)
    }
}

/// Bounded, non-blocking JSONL writer: unique 0600 file in a 0700 directory,
/// never overwriting; 10 min / 1 MiB / 200 records (including the start) / 32 pending.
final class ProfileDiagnosticsLog {
    struct Limits {
        var seconds: TimeInterval = 600
        var bytes = 1_048_576
        var records = 200
        var pending = 32
    }
    private struct Line: Encodable {
        let schema = 1
        let session: UInt64
        let ordinal: Int
        let elapsedMilliseconds: Int
        let event: ProfileDiagnostics.Event
        let values: ProfileDiagnostics.Values
    }

    let fileURL: URL
    let session: UInt64
    private let descriptor: Int32
    private let writer: DispatchQueue
    private let slots: DispatchSemaphore
    private let writes = DispatchGroup()
    private let lock = NSLock()
    private let clock: () -> TimeInterval
    private let started: TimeInterval
    private let limits: Limits
    private var reserved = 0
    private var closed = false
    private var outputFailed = false
    private var pendingWrites = 0
    // Writer-queue owned.
    private var writtenBytes = 0
    private var writeFailed = false

    init?(directory: URL, session: UInt64, limits: Limits = .init(),
          clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
          writerQueue: DispatchQueue? = nil) {
        guard limits.seconds > 0, limits.seconds.isFinite, limits.bytes > 0,
              limits.records > 0, limits.pending > 0 else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        var template = Array(directory.appendingPathComponent("profile-diagnostics-XXXXXX").path.utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { return nil }
        guard fchmod(fd, S_IRUSR | S_IWUSR) == 0 else {
            Darwin.close(fd)
            template.withUnsafeBufferPointer { _ = unlink($0.baseAddress!) }
            return nil
        }
        descriptor = fd
        fileURL = URL(fileURLWithPath: template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
        self.session = session
        self.limits = limits
        self.clock = clock
        started = clock()
        writer = writerQueue ?? DispatchQueue(label: "TileLauncher.profile-diagnostic-writer", qos: .utility)
        slots = DispatchSemaphore(value: limits.pending)
    }
    deinit { Darwin.close(descriptor) }

    /// Permanent eligibility: open, within time/record caps, no write failure.
    /// A temporarily full pending queue does not end a session.
    var isAccepting: Bool {
        let now = clock()
        lock.lock(); defer { lock.unlock() }
        return !closed && !outputFailed && now >= started && now - started <= limits.seconds && reserved < limits.records
    }
    /// `isAccepting` and a free pending slot right now (best effort).
    var canRecordNow: Bool {
        let now = clock()
        lock.lock(); defer { lock.unlock() }
        return !closed && !outputFailed && now >= started && now - started <= limits.seconds
            && reserved < limits.records && pendingWrites < limits.pending
    }

    /// Non-blocking; false when full, expired, closed or the pending queue is full.
    @discardableResult
    func record(_ event: ProfileDiagnostics.Event, _ values: ProfileDiagnostics.Values = .init()) -> Bool {
        guard slots.wait(timeout: .now()) == .success else { return false }
        let now = clock()
        lock.lock()
        guard !closed, !outputFailed, now >= started, now - started <= limits.seconds, reserved < limits.records else {
            lock.unlock(); slots.signal(); return false
        }
        reserved += 1
        pendingWrites += 1
        let line = Line(session: session, ordinal: reserved,
                        elapsedMilliseconds: Int((max(0, now - started) * 1000).rounded()), event: event, values: values)
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
            guard writtenBytes <= limits.bytes, data.count <= limits.bytes - writtenBytes else { writeFailed = true; return }
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

    /// Stops new records and waits at most `timeout` (≤ 1 s) for accepted writes.
    @discardableResult
    func finish(timeout: TimeInterval = 1) -> Bool {
        lock.lock(); closed = true; lock.unlock()
        return writes.wait(timeout: .now() + max(0, min(timeout, 1))) == .success
    }
}

/// Thread-safe weak link from the existing `ProfileQuery.entities(for:)` to the
/// current session's log. Receives counts only — never identifiers, profile
/// objects or errors. A token stays bound to the log it began with; after
/// stop/expiry that log rejects writes (or is gone), so nothing is rebound.
final class ProfileDiagnosticsEntityBridge {
    static let shared = ProfileDiagnosticsEntityBridge()
    struct Token {
        fileprivate weak var log: ProfileDiagnosticsLog?
        fileprivate let ordinal: Int
    }
    private let lock = NSLock()
    private weak var log: ProfileDiagnosticsLog?
    private var ordinal = 0
    init() {}

    func install(_ log: ProfileDiagnosticsLog) { lock.lock(); self.log = log; lock.unlock() }
    /// Removes only the same log.
    func remove(_ log: ProfileDiagnosticsLog) {
        lock.lock(); if self.log === log { self.log = nil }; lock.unlock()
    }
    func begin(requestedCount: Int) -> Token? {
        lock.lock()
        guard let log, log.isAccepting else { lock.unlock(); return nil }
        ordinal += 1
        let token = Token(log: log, ordinal: ordinal)
        lock.unlock()
        log.record(.entityQueryStarted, .init(query: token.ordinal, requestedCount: requestedCount))
        return token
    }
    func finish(_ token: Token?, resolvedCount: Int?, failed: Bool) {
        guard let token, let log = token.log else { return }
        log.record(.entityQueryCompleted, .init(query: token.ordinal, outcome: failed ? .error : nil,
                                                resolvedCount: failed ? nil : resolvedCount))
    }
}

/// Session owner; main thread only. Runtime starts OFF; only `start()`
/// (status menu) begins a session. Everything is a no-op, and no product state
/// or Focus is read, while no session is recording.
final class ProfileDiagnosticsRecorder {
    static let shared = ProfileDiagnosticsRecorder()

    struct QueryToken {
        fileprivate let session: UInt64
        fileprivate let ordinal: Int
        fileprivate let serial: Int
        fileprivate let before: String?
    }
    private final class Session {
        let log: ProfileDiagnosticsLog
        var queries = 0
        var observerReads = 0
        var skippedObservations = 0
        var pendingObserver: Int?
        var timedOutObserver: Int?
        /// Last successful observer result in this session; `.none` before the first.
        var lastObserved: String??
        /// RAM only; outer nil means no known notification state in this session.
        var lastNotification: String??
        init(log: ProfileDiagnosticsLog) { self.log = log }
    }

    static let maximumObserverReads = 12
    static let observerTimeout: TimeInterval = 2

    let directory: URL
    /// Set by the delegate; called only while recording.
    var stateProvider: (() -> ProfileDiagnostics.State?)?
    private let limits: ProfileDiagnosticsLog.Limits
    private let clock: () -> TimeInterval
    private let writerQueue: DispatchQueue?
    private let observer: () async throws -> String?
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let entityBridge: ProfileDiagnosticsEntityBridge
    private var session: Session?
    private var epoch: UInt64 = 0
    private var notificationSerial = 0
    /// Process-wide for this recorder: survives stop/restart until the OS call returns.
    private(set) var observerInFlight = false

    init(directory: URL = ProfileDiagnostics.defaultDirectory, limits: ProfileDiagnosticsLog.Limits = .init(),
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         writerQueue: DispatchQueue? = nil,
         observer: @escaping () async throws -> String? = { try await LauncherFocusIntent.current.profile?.id },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         },
         entityBridge: ProfileDiagnosticsEntityBridge = .shared) {
        self.directory = directory
        self.limits = limits
        self.clock = clock
        self.writerQueue = writerQueue
        self.observer = observer
        self.schedule = schedule
        self.entityBridge = entityBridge
    }

    /// False (and no state read) once the session ended or expired.
    var isRecording: Bool { activeSession() != nil }
    var currentFileURL: URL? { activeSession()?.log.fileURL }
    var currentSession: UInt64? { activeSession().map { $0.log.session } }

    /// Starts a new session with a new unique file and epoch. A recording
    /// session is kept (returns false); no duplicate logger is created.
    @discardableResult
    func start() -> Bool {
        if activeSession() != nil { return false }
        epoch &+= 1
        guard let log = ProfileDiagnosticsLog(directory: directory, session: epoch, limits: limits, clock: clock,
                                              writerQueue: writerQueue) else { return false }
        session = Session(log: log)
        emit(.started, .init(snapshot: state()?.snapshot))
        entityBridge.install(log)
        requestObservation(.recordingStart)
        return true
    }
    /// Records `stopped` and drains accepted writes (bounded). An expired/full
    /// session ends without reading state. An in-flight observer read is
    /// detached, not interrupted: its result is discarded and it keeps the
    /// global gate until the OS call actually returns.
    func stop() {
        guard let current = activeSession() else { return }
        current.log.record(.stopped, .init(snapshot: state()?.snapshot))
        end(current, drain: 1)
    }

    func noteFocusPerform(hasProfile: Bool) {
        guard activeSession() != nil else { return }
        emit(.focusPerform, .init(hasProfile: hasProfile))
    }
    /// After the existing notification assignment.
    func noteFocusNotification(hasProfile: Bool, changed: Bool) {
        guard let current = activeSession() else { return }
        notificationSerial += 1
        let state = state()
        current.lastNotification = state.map { $0.focusProfileID }
        emit(.focusNotification, .init(hasProfile: hasProfile, changed: changed, notificationSerial: notificationSerial,
                                       snapshot: state?.snapshot))
    }
    /// Before an existing product `.current` query; nil (and no state read) when not recording.
    func beginQuery(_ source: ProfileDiagnostics.Source) -> QueryToken? {
        guard let current = activeSession() else { return nil }
        current.queries += 1
        let token = QueryToken(session: current.log.session, ordinal: current.queries, serial: notificationSerial,
                               before: state()?.focusProfileID)
        emit(.queryStarted, .init(source: source, query: token.ordinal, notificationSerial: notificationSerial))
        return token
    }
    /// After the existing assignment (or catch). Results of an older session are dropped.
    func completeQuery(_ token: QueryToken?, source: ProfileDiagnostics.Source, returned: String?, failed: Bool) {
        guard let token, let current = activeSession(), current.log.session == token.session else { return }
        let state = state()
        let outcome: ProfileDiagnostics.Outcome = failed ? .error : returned == nil ? .noProfile : .profile
        emit(.queryCompleted, .init(source: source, query: token.ordinal, outcome: outcome,
                                    changed: state.map { $0.focusProfileID != token.before },
                                    returnedPresent: failed ? nil : returned != nil,
                                    returnedMember: failed ? nil : returned.flatMap { id in state.map { $0.profileIDs.contains(id) } },
                                    returnedMatchesLatestNotification: failed || notificationSerial <= token.serial
                                        ? nil : current.lastNotification.map { $0 == returned },
                                    notificationSerial: notificationSerial,
                                    notificationsSinceStart: notificationSerial - token.serial,
                                    snapshot: state?.snapshot))
    }
    func noteInvocation(_ invocation: ProfileDiagnostics.Invocation, held: Bool? = nil) {
        guard activeSession() != nil else { return }
        emit(.invocation, .init(invocation: invocation, held: held, snapshot: state()?.snapshot))
    }

    /// Diagnostic-only Focus read: at most one in flight (globally), at most 12
    /// per session; the result is only observed, never assigned. The 2 s mark
    /// is relative to request admission, not proof that the OS call began or
    /// a forced OS timeout. It only records a mark and does not release the gate.
    /// `changed` compares with the last successful observer result of the same
    /// session (nil for the first success; errors do not replace it).
    func requestObservation(_ purpose: ProfileDiagnostics.Purpose) {
        guard let current = activeSession() else { return }
        // No optional OS work when the writer cannot take a record right now.
        guard !observerInFlight, current.observerReads < Self.maximumObserverReads, current.log.canRecordNow else {
            current.skippedObservations += 1
            return
        }
        observerInFlight = true
        current.observerReads += 1
        let ordinal = current.observerReads, sessionID = current.log.session, serial = notificationSerial
        current.pendingObserver = ordinal
        emit(.observerRequested, .init(purpose: purpose, query: ordinal, notificationSerial: serial,
                                     observerReads: ordinal, skippedObservations: current.skippedObservations))
        schedule(Self.observerTimeout) { [weak self] in
            guard let self, let live = self.activeSession(), live.log.session == sessionID,
                  live.pendingObserver == ordinal else { return }
            live.timedOutObserver = ordinal
            self.emit(.observerTimeout, .init(purpose: purpose, query: ordinal, timedOut: true))
        }
        let observer = self.observer
        Task { @MainActor [weak self] in
            // A menu stop/restart or expiry can happen after scheduling but
            // before this task gets its first turn. No OS call has started yet,
            // so rejecting here may safely release the global in-flight gate.
            do {
                guard let live = self?.activeSession(), live.log.session == sessionID, live.log.canRecordNow else {
                    self?.observerInFlight = false
                    if let live = self?.session, live.log.session == sessionID { live.pendingObserver = nil }
                    return
                }
            }
            let returned: String?, failed: Bool
            do { returned = try await observer(); failed = false } catch { returned = nil; failed = true }
            guard let self else { return }
            // Only the actual return releases the global gate.
            self.observerInFlight = false
            guard let live = self.activeSession(), live.log.session == sessionID else { return }
            if live.pendingObserver == ordinal { live.pendingObserver = nil }
            let timedOut = live.timedOutObserver == ordinal
            let changed: Bool? = failed ? nil : live.lastObserved.map { $0 != returned }
            if !failed { live.lastObserved = .some(returned) }
            let state = self.state()
            self.emit(.observerCompleted, .init(
                purpose: purpose, query: ordinal,
                outcome: failed ? .error : returned == nil ? .noProfile : .profile,
                changed: changed,
                returnedPresent: failed ? nil : returned != nil,
                returnedMember: failed ? nil : returned.flatMap { id in state.map { $0.profileIDs.contains(id) } },
                returnedMatchesCached: failed ? nil : state.map { $0.focusProfileID == returned },
                returnedMatchesLatestNotification: failed || self.notificationSerial <= serial
                    ? nil : live.lastNotification.map { $0 == returned },
                notificationSerial: self.notificationSerial,
                notificationsSinceStart: self.notificationSerial - serial,
                timedOut: timedOut, snapshot: state?.snapshot))
        }
    }

    private func activeSession() -> Session? {
        guard let current = session else { return nil }
        if current.log.isAccepting { return current }
        // Expired, full or failed: recording ends; nothing further is read or written.
        end(current, drain: 0)
        return nil
    }
    private func end(_ current: Session, drain: TimeInterval) {
        entityBridge.remove(current.log)
        if session === current { session = nil }
        current.log.finish(timeout: drain)
    }
    private func state() -> ProfileDiagnostics.State? { stateProvider?() }
    private func emit(_ event: ProfileDiagnostics.Event, _ values: ProfileDiagnostics.Values) {
        guard let current = session else { return }
        current.log.record(event, values)
    }
}

/// Status-menu items: start / open folder / stop. Opening only shows the
/// dedicated diagnostics directory.
final class ProfileDiagnosticsMenuController: NSObject, NSMenuItemValidation {
    let recorder: ProfileDiagnosticsRecorder
    init(recorder: ProfileDiagnosticsRecorder = .shared) { self.recorder = recorder }

    func makeItems() -> [NSMenuItem] {
        let start = NSMenuItem(title: "프로필 진단 시작", action: #selector(startDiagnostics(_:)), keyEquivalent: "")
        let open = NSMenuItem(title: "프로필 진단 로그 폴더 열기", action: #selector(openDiagnosticsFolder(_:)), keyEquivalent: "")
        let stop = NSMenuItem(title: "프로필 진단 중지", action: #selector(stopDiagnostics(_:)), keyEquivalent: "")
        for item in [start, open, stop] { item.target = self }
        return [start, open, stop]
    }
    @objc func startDiagnostics(_ sender: Any?) { recorder.start() }
    @objc func stopDiagnostics(_ sender: Any?) { recorder.stop() }
    @objc func openDiagnosticsFolder(_ sender: Any?) {
        try? FileManager.default.createDirectory(at: recorder.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(recorder.directory)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(startDiagnostics(_:)): return !recorder.isRecording
        case #selector(stopDiagnostics(_:)): return recorder.isRecording
        default: return true
        }
    }
}
#endif
