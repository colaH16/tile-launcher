#if TILE_LAUNCHER_DIAGNOSTICS && TILE_LAUNCHER_PROFILE_DIAGNOSTICS
import AppKit
import DeckCore
import Foundation

/// Synthetic settings, clocks, writer queues and manually completed async
/// providers only. No actual Focus/current, AX, user settings or app actions.
enum ProfileDiagnosticsValidation {
    @MainActor private final class Observer {
        private(set) var calls = 0
        private var pending: [CheckedContinuation<String?, Error>] = []
        func read() async throws -> String? {
            calls += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func succeed(_ value: String?) { pending.removeFirst().resume(returning: value) }
        func fail() {
            pending.removeFirst().resume(throwing: NSError(domain: "PRIVATE_ERROR_DOMAIN", code: 987,
                userInfo: [NSLocalizedDescriptionKey: "PRIVATE_ERROR_DESCRIPTION"]))
        }
    }

    @MainActor static func verify(to directory: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("profile-validation-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else {
                // All callers pass fixed fixture descriptions, never user or
                // provider error text; keep Debug failures actionable privately.
                fputs("Profile diagnostics fixture failed: \(message)\n", stderr)
                throw NSError(domain: "TileLauncher.ProfileDiagnosticsValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func settle(_ condition: () -> Bool) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                await Task.yield()
            }
            try check(condition(), "Synthetic async provider did not settle")
        }
        func rows(_ url: URL) throws -> [[String: Any]] {
            try Data(contentsOf: url).split(separator: 0x0a).map {
                guard let row = try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] else {
                    throw NSError(domain: "TileLauncher.ProfileDiagnosticsValidation", code: 2)
                }
                return row
            }
        }
        func events(_ rows: [[String: Any]], _ event: String) -> [[String: Any]] {
            rows.filter { $0["event"] as? String == event }
        }
        func values(_ row: [String: Any]) -> [String: Any] { row["values"] as? [String: Any] ?? [:] }

        let suite = "dev.cola16.TileLauncher.profile-validation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, persistsChanges: false)
        let manual = "PRIVATE_PROFILE_MANUAL", work = "PRIVATE_PROFILE_WORK", worship = "PRIVATE_PROFILE_WORSHIP"
        store.profiles = [manual, work, worship].map { LauncherProfile(id: $0, name: "PRIVATE_NAME_" + $0) }
        store.manualProfileID = manual
        var visible: String? = manual
        var panelVisible = true
        func snapshot() -> ProfileDiagnostics.Snapshot {
            .make(settings: store, presentationProfileID: visible, panelVisible: panelVisible)
        }
        store.focusProfileID = work; store.followFocus = false
        try check(snapshot().reason == .manual && snapshot().activeMatchesReason,
                  "Disabled automatic selection must reflect the real manual policy")
        store.followFocus = true
        try check(snapshot().reason == .focus && snapshot().focusMember && snapshot().presentationMatchesActive == false,
                  "A valid Focus selection and stale visible profile must be reported independently")
        visible = work
        try check(snapshot().presentationMatchesActive == true, "Matching visible and active profiles must be recognized")
        store.focusProfileID = nil
        try check(snapshot().reason == .manual && !snapshot().focusIDPresent,
                  "A cleared filter must differ from an unknown non-nil ID")
        store.focusProfileID = "PRIVATE_DELETED_ID"
        try check(snapshot().reason == .manual && snapshot().focusIDPresent && !snapshot().focusMember,
                  "A stale ID must report presence and failed membership separately")
        store.manualProfileID = "PRIVATE_MISSING_MANUAL"
        try check(snapshot().reason == .firstFallback && snapshot().activeMatchesReason,
                  "Missing manual ID must reflect the actual first-profile fallback")
        store.manualProfileID = manual; store.focusProfileID = nil; visible = nil; panelVisible = false
        try check(snapshot().presentationMatchesActive == nil && !snapshot().presentationProfilePresent,
                  "A closed/absent presentation is not a stale visible profile")

        var now: TimeInterval = 100
        var stateReads = 0
        var scheduled: [@MainActor () -> Void] = []
        let provider = Observer()
        let bridge = ProfileDiagnosticsEntityBridge()
        let queue = DispatchQueue(label: "TileLauncher.profile-validation.writer")
        let logs = root.appendingPathComponent("sessions", isDirectory: true)
        let recorder = ProfileDiagnosticsRecorder(directory: logs, clock: { now }, writerQueue: queue,
            observer: { try await provider.read() }, schedule: { _, callback in scheduled.append(callback) }, entityBridge: bridge)
        recorder.stateProvider = {
            stateReads += 1
            return .init(focusProfileID: store.focusProfileID, profileIDs: Set(store.profiles.map(\.id)), snapshot: snapshot())
        }
        recorder.noteInvocation(.show, held: true)
        recorder.noteFocusPerform(hasProfile: true)
        recorder.noteFocusNotification(hasProfile: true, changed: true)
        recorder.requestObservation(.show)
        let inactiveToken = recorder.beginQuery(.wake)
        recorder.completeQuery(inactiveToken, source: .wake, returned: work, failed: false)
        try check(bridge.begin(requestedCount: 2) == nil, "Inactive entity resolution must create no diagnostic work")
        try check(!recorder.isRecording && inactiveToken == nil && stateReads == 0 && provider.calls == 0
                  && !fm.fileExists(atPath: logs.path), "Runtime OFF must create no file or query/snapshot work")
        let menu = ProfileDiagnosticsMenuController(recorder: recorder)
        let items = menu.makeItems()
        try check(items.map(\.title) == ["프로필 진단 시작", "프로필 진단 로그 폴더 열기", "프로필 진단 중지"]
                  && menu.validateMenuItem(items[0]) && !menu.validateMenuItem(items[2]), "Menu opt-in must start inactive")

        try check(recorder.start(), "First menu start must create a session")
        guard let firstURL = recorder.currentFileURL else { throw NSError(domain: "TileLauncher.ProfileDiagnosticsValidation", code: 3) }
        try check(!recorder.start() && recorder.currentFileURL == firstURL, "Repeated start must preserve the active file")
        try check(!menu.validateMenuItem(items[0]) && menu.validateMenuItem(items[2]), "Recording menu states must reflect the session")
        try await settle { provider.calls == 1 }
        recorder.requestObservation(.show)
        now += 2
        scheduled[0]()
        try check(recorder.observerInFlight && provider.calls == 1, "Timeout and coalescing must never free an unfinished OS call")
        let oldQuery = recorder.beginQuery(.wake)
        let oldEntity = bridge.begin(requestedCount: 1)
        recorder.stop()
        let firstData = try Data(contentsOf: firstURL)
        try check(!recorder.isRecording && recorder.observerInFlight, "Stop detaches the result while preserving the global in-flight gate")
        try check(recorder.start(), "Restart must create a fresh recording session")
        guard let secondURL = recorder.currentFileURL else { throw NSError(domain: "TileLauncher.ProfileDiagnosticsValidation", code: 4) }
        try check(firstURL != secondURL, "Sessions must never overwrite an earlier diagnostic file")
        recorder.completeQuery(oldQuery, source: .wake, returned: work, failed: false)
        bridge.finish(oldEntity, resolvedCount: 0, failed: false)
        provider.succeed(work)
        try await settle { !recorder.observerInFlight }
        queue.sync {}
        try check(events(try rows(secondURL), "observerCompleted").isEmpty
                  && events(try rows(secondURL), "queryCompleted").isEmpty,
                  "Old observer/query completion must not enter a new session")

        // Current probes observe IDs without applying them to the product store.
        let beforeProbe = store.focusProfileID
        func completeProbe(_ returned: String?, failed: Bool = false, timedOut: Bool = false) async throws {
            let beforeCalls = provider.calls
            recorder.requestObservation(.show)
            try await settle { provider.calls == beforeCalls + 1 }
            if timedOut { now += 2; scheduled.last?() }
            if failed { provider.fail() } else { provider.succeed(returned) }
            try await settle { !recorder.observerInFlight }
        }
        try await completeProbe(work, timedOut: true)
        try await completeProbe(worship)
        try await completeProbe(worship)
        try await completeProbe(nil, failed: true)
        try await completeProbe(worship)
        try await completeProbe(nil)
        try await completeProbe(nil)
        try check(store.focusProfileID == beforeProbe, "Diagnostic current results must never apply product state")
        queue.sync {}
        var observations = events(try rows(secondURL), "observerCompleted").map(values)
        try check(observations.count == 7 && observations[0]["changed"] == nil
                  && observations[1]["changed"] as? Bool == true && observations[2]["changed"] as? Bool == false
                  && observations[3]["outcome"] as? String == "error" && observations[3]["changed"] == nil
                  && observations[4]["changed"] as? Bool == false && observations[5]["changed"] as? Bool == true
                  && observations[6]["changed"] as? Bool == false,
                  "Per-session successful observer ID changes must survive an intervening error and distinguish repeated IDs")
        try check(observations[0]["returnedMember"] as? Bool == true
                  && observations[0]["returnedMatchesCached"] as? Bool == false
                  && observations[0]["timedOut"] as? Bool == true,
                  "OS-observed membership and stale cached Focus state must remain separate")
        for _ in 7..<ProfileDiagnosticsRecorder.maximumObserverReads { try await completeProbe(nil) }
        let callsAtCap = provider.calls
        recorder.requestObservation(.show)
        await Task.yield()
        try check(provider.calls == callsAtCap && !recorder.observerInFlight,
                  "The per-session observer count must stop at twelve without starting more work")

        // Reproduce the old-query-after-new-notification ordering, without
        // correcting it: diagnostic values must show the overwrite relationship.
        store.focusProfileID = work
        let query = recorder.beginQuery(.wake)
        store.focusProfileID = worship
        recorder.noteFocusNotification(hasProfile: true, changed: true)
        store.focusProfileID = work
        recorder.completeQuery(query, source: .wake, returned: work, failed: false)
        let matchingQuery = recorder.beginQuery(.wake)
        store.focusProfileID = worship
        recorder.noteFocusNotification(hasProfile: true, changed: true)
        recorder.completeQuery(matchingQuery, source: .wake, returned: worship, failed: false)
        let nilQuery = recorder.beginQuery(.autoSelect)
        store.focusProfileID = nil
        recorder.completeQuery(nilQuery, source: .autoSelect, returned: nil, failed: false)
        let errorQuery = recorder.beginQuery(.appLaunch)
        recorder.completeQuery(errorQuery, source: .appLaunch, returned: nil, failed: true)
        recorder.noteInvocation(.temporaryCycle)
        recorder.noteFocusPerform(hasProfile: true)
        let resolved = bridge.begin(requestedCount: 2)
        bridge.finish(resolved, resolvedCount: 1, failed: false)
        let missing = bridge.begin(requestedCount: 1)
        bridge.finish(missing, resolvedCount: 0, failed: false)
        let resolutionError = bridge.begin(requestedCount: 1)
        bridge.finish(resolutionError, resolvedCount: nil, failed: true)
        recorder.stop()
        let sessionRows = try rows(secondURL)
        let completed = events(sessionRows, "queryCompleted").map(values)
        try check(completed.count == 4 && completed[0]["notificationsSinceStart"] as? Int == 1
                  && completed[0]["outcome"] as? String == "profile"
                  && completed[0]["returnedMatchesLatestNotification"] as? Bool == false
                  && completed[1]["returnedMatchesLatestNotification"] as? Bool == true
                  && completed[2]["outcome"] as? String == "noProfile"
                  && completed[2]["returnedPresent"] as? Bool == false && completed[2]["returnedMatchesLatestNotification"] == nil
                  && completed[3]["outcome"] as? String == "error" && completed[3]["returnedPresent"] == nil,
                  "Current nil/error/success and intervening notification must have distinct metadata")
        try check(store.focusProfileID == nil, "Recording must not repair or otherwise alter product query assignments")
        let entityStarts = events(sessionRows, "entityQueryStarted").map(values)
        let entityResults = events(sessionRows, "entityQueryCompleted").map(values)
        try check(entityStarts.count == 3 && entityStarts[0]["requestedCount"] as? Int == 2
                  && entityResults.count == 3 && entityResults[0]["resolvedCount"] as? Int == 1
                  && entityResults[1]["resolvedCount"] as? Int == 0
                  && entityResults[2]["outcome"] as? String == "error" && entityResults[2]["resolvedCount"] == nil,
                  "Existing entity resolution must expose only requested/resolved counts and fixed failure metadata")
        try check(try Data(contentsOf: firstURL) == firstData, "A new session must never overwrite the previous log")
        let afterStopReads = stateReads
        recorder.noteInvocation(.show); recorder.requestObservation(.show); recorder.stop()
        try check(stateReads == afterStopReads, "Stopped diagnostics must not read snapshots")
        let permissions = try fm.attributesOfItem(atPath: firstURL.path)[.posixPermissions] as? NSNumber
        let folderPermissions = try fm.attributesOfItem(atPath: logs.path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue == 0o600 && folderPermissions?.intValue == 0o700, "Files/directories must be private")

        // A task can still be queued when the menu stops or time expires. It
        // must recheck its captured session before starting any OS provider.
        for expire in [false, true] {
            var queuedTime: TimeInterval = 1
            let queuedProvider = Observer()
            let queued = ProfileDiagnosticsRecorder(directory: root.appendingPathComponent(expire ? "queued-expiry" : "queued-stop"),
                clock: { queuedTime }, writerQueue: queue, observer: { try await queuedProvider.read() }, schedule: { _, _ in },
                entityBridge: ProfileDiagnosticsEntityBridge())
            try check(queued.start(), "Queued observation fixture starts")
            if expire { queuedTime += 601 } else { queued.stop() }
            try await settle { !queued.observerInFlight || queuedProvider.calls > 0 }
            let incorrectlyStarted = queuedProvider.calls > 0
            if incorrectlyStarted {
                queuedProvider.succeed(nil)
                try await settle { !queued.observerInFlight }
            }
            queued.stop()
            try check(!incorrectlyStarted, "A stopped/expired session must not begin an already queued observer read")
        }
        let replacedProvider = Observer()
        let replaced = ProfileDiagnosticsRecorder(directory: root.appendingPathComponent("queued-restart"),
            writerQueue: queue, observer: { try await replacedProvider.read() }, schedule: { _, _ in },
            entityBridge: ProfileDiagnosticsEntityBridge())
        try check(replaced.start(), "Queued restart fixture starts")
        replaced.stop()
        try check(replaced.start(), "Queued restart keeps old unfinished gate until its task turn")
        try await settle { !replaced.observerInFlight || replacedProvider.calls > 0 }
        let wronglyRebound = replacedProvider.calls > 0
        if wronglyRebound {
            replacedProvider.succeed(nil)
            try await settle { !replaced.observerInFlight }
        }
        replaced.stop()
        try check(!wronglyRebound, "An old queued task must not adopt a newer session or start its provider")

        // Expired stop must short-circuit argument evaluation, not take one last
        // product snapshot merely to build a record that will be rejected.
        var expiryTime: TimeInterval = 10
        var expiryReads = 0
        let expiryProvider = Observer()
        var shortLimits = ProfileDiagnosticsLog.Limits(); shortLimits.seconds = 1
        let expiry = ProfileDiagnosticsRecorder(directory: root.appendingPathComponent("expiry"), limits: shortLimits,
            clock: { expiryTime }, writerQueue: queue, observer: { try await expiryProvider.read() }, schedule: { _, _ in })
        expiry.stateProvider = { expiryReads += 1; return nil }
        try check(expiry.start(), "Expiry fixture start")
        try await settle { expiryProvider.calls == 1 }
        expiryProvider.succeed(nil)
        try await settle { !expiry.observerInFlight }
        let readsBeforeExpiry = expiryReads
        expiryTime = 11.01
        expiry.stop()
        try check(expiryReads == readsBeforeExpiry && !expiry.isRecording, "Expired stop must perform zero state reads")

        // Temporary writer backpressure cannot end the session or start an
        // optional read whose start cannot be recorded.
        let paused = DispatchQueue(label: "TileLauncher.profile-validation.paused")
        paused.suspend()
        var resumePaused = true
        defer { if resumePaused { paused.resume() } }
        var pendingLimits = ProfileDiagnosticsLog.Limits(); pendingLimits.pending = 1
        let pendingProvider = Observer()
        let pending = ProfileDiagnosticsRecorder(directory: root.appendingPathComponent("pending"), limits: pendingLimits,
            writerQueue: paused, observer: { try await pendingProvider.read() }, schedule: { _, _ in })
        try check(pending.start() && pending.isRecording, "Full writer backlog must remain a live session")
        await Task.yield()
        try check(pendingProvider.calls == 0, "A full pending queue must skip optional current work")
        paused.resume(); resumePaused = false; paused.sync {}
        pending.requestObservation(.show)
        // The observerRequested event itself uses the only writer slot. Drain
        // that known event before yielding to the queued Task, so its live
        // capacity recheck observes a free slot rather than correctly skipping.
        paused.sync {}
        try await settle { pendingProvider.calls == 1 }
        pendingProvider.succeed(nil)
        try await settle { !pending.observerInFlight }
        pending.stop()

        var headerLimits = ProfileDiagnosticsLog.Limits(); headerLimits.records = 1
        var headerProviderCalls = 0
        let headerDirectory = root.appendingPathComponent("header-cap")
        let headerOnly = ProfileDiagnosticsRecorder(directory: headerDirectory, limits: headerLimits, writerQueue: queue,
            observer: { headerProviderCalls += 1; return nil }, schedule: { _, _ in },
            entityBridge: ProfileDiagnosticsEntityBridge())
        try check(headerOnly.start() && !headerOnly.isRecording && headerProviderCalls == 0,
                  "The start record counts toward the event cap and prevents optional queries when exhausted")
        queue.sync {}
        let headerFiles = try fm.contentsOfDirectory(at: headerDirectory, includingPropertiesForKeys: nil)
        try check(headerFiles.count == 1 && (try rows(headerFiles[0])).count == 1
                  && (try rows(headerFiles[0]))[0]["event"] as? String == "started",
                  "Header-only limits serialize exactly one start event")

        var recordLimits = ProfileDiagnosticsLog.Limits(); recordLimits.records = 3
        guard let capped = ProfileDiagnosticsLog(directory: root.appendingPathComponent("records"), session: 90,
                                                 limits: recordLimits, writerQueue: queue) else {
            throw NSError(domain: "TileLauncher.ProfileDiagnosticsValidation", code: 5)
        }
        var accepted = 0
        for _ in 0..<20 { if capped.record(.invocation) { accepted += 1 } }
        try check(accepted == 3 && !capped.isAccepting && capped.finish() && (try rows(capped.fileURL)).count == 3,
                  "Configured event cap must bound both reservation and serialized lines")
        var byteLimits = ProfileDiagnosticsLog.Limits(); byteLimits.bytes = 200
        guard let bytes = ProfileDiagnosticsLog(directory: root.appendingPathComponent("bytes"), session: 91,
                                                limits: byteLimits, writerQueue: queue) else {
            throw NSError(domain: "TileLauncher.ProfileDiagnosticsValidation", code: 6)
        }
        for _ in 0..<10 { bytes.record(.invocation, .init(invocation: .temporaryCycle)) }
        queue.sync {}
        try check(!bytes.isAccepting && bytes.finish() && (try Data(contentsOf: bytes.fileURL)).count <= byteLimits.bytes,
                  "Byte exhaustion must stop the writer before a partial JSON line")
        _ = try rows(bytes.fileURL)

        let allowedStrings: Set<String> = ["started", "stopped", "focusPerform", "focusNotification", "queryStarted", "queryCompleted",
            "observerRequested", "observerCompleted", "observerTimeout", "invocation", "appLaunch", "wake", "autoSelect", "recordingStart",
            "show", "profile", "noProfile", "error", "hide", "present", "manualSelection", "followFocusSelection", "temporaryCycle",
            "focus", "manual", "firstFallback", "entityQueryStarted", "entityQueryCompleted"]
        func inspect(_ value: Any) throws {
            if let text = value as? String {
                try check(allowedStrings.contains(text), "Serialized strings must be fixed diagnostic enums only")
            } else if let map = value as? [String: Any] {
                for child in map.values { try inspect(child) }
            } else if let list = value as? [Any] {
                for child in list { try inspect(child) }
            }
        }
        let all = try rows(firstURL) + sessionRows
        for row in all {
            try check(Set(row.keys) == ["schema", "session", "ordinal", "elapsedMilliseconds", "event", "values"],
                      "Only the fixed profile diagnostic schema may be serialized")
            try inspect(row)
        }
        let raw = try String(contentsOf: firstURL, encoding: .utf8) + String(contentsOf: secondURL, encoding: .utf8)
        try check(!raw.contains("PRIVATE_") && !raw.contains("/Applications/") && !raw.contains("NSLocalizedDescription"),
                  "IDs/names/error details must never leave typed metadata")
        try check(events(try rows(firstURL), "observerTimeout").count == 1, "Timeout must be one correlated event, not polling")
        observations = events(sessionRows, "observerCompleted").map(values)
        try check(observations.count == 12 && provider.calls == 13, "No live/default provider or extra observation may run")
        print("Profile diagnostics: real isolated selection snapshots, inactive zero work, async session/probe limits, nil/error/notification ordering, private bounded logs and menu opt-in verified with no live Focus queries.")
    }
}
#endif
