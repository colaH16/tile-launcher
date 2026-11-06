#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import Darwin
import Foundation
import ApplicationServices

/// Synthetic file/queue fixtures only. Does not observe apps, install a global
/// input monitor, query AX, open a panel or acquire the production instance.
enum MenuCaptureDiagnosticsValidation {
    static func verify(to directory: URL) throws {
        let fm = FileManager.default
        let root = directory.appendingPathComponent("menu-capture-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else {
                throw NSError(domain: "TileLauncher.MenuCaptureDiagnosticsValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func logger(_ folder: String, limits: MenuCaptureDiagnostics.Limits = .init(),
                    clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    queue: DispatchQueue? = nil) throws -> MenuCaptureDiagnostics {
            let target = root.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            guard let value = MenuCaptureDiagnostics(directory: target, limits: limits, clock: clock, writerQueue: queue) else {
                throw NSError(domain: "TileLauncher.MenuCaptureDiagnosticsValidation", code: 2)
            }
            return value
        }
        func lines(_ value: MenuCaptureDiagnostics) throws -> [[String: Any]] {
            try Data(contentsOf: value.fileURL).split(separator: 0x0a).map {
                guard let result = try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] else {
                    throw NSError(domain: "TileLauncher.MenuCaptureDiagnosticsValidation", code: 3)
                }
                return result
            }
        }

        let noOpt = root.appendingPathComponent("not-opted-in", isDirectory: true)
        try fm.createDirectory(at: noOpt, withIntermediateDirectories: true)
        try check(MenuCaptureDiagnostics.makeIfRequested(arguments: ["TileLauncher"], directory: noOpt) == nil,
                  "No diagnostic logger without the explicit execution argument")
        try check(try fm.contentsOfDirectory(atPath: noOpt.path).isEmpty,
                  "An invocation without opt-in must create no file")

        let a = try logger("unique")
        let existing = Data("existing-file-preserved".utf8)
        let sentinel = a.fileURL.deletingLastPathComponent().appendingPathComponent("tile-launcher-menu-capture-existing")
        try existing.write(to: sentinel)
        guard let b = MenuCaptureDiagnostics(directory: a.fileURL.deletingLastPathComponent()) else {
            throw NSError(domain: "TileLauncher.MenuCaptureDiagnosticsValidation", code: 4)
        }
        try check(a.fileURL != b.fileURL, "Every run must create a unique file")
        let permission = try fm.attributesOfItem(atPath: a.fileURL.path)[.posixPermissions] as? NSNumber
        try check(permission?.intValue == 0o600, "Diagnostic file permissions must be 0600")
        a.updateContext(.init(generation: 4, helpSession: 2))
        let origin = a.stamp()
        try check(a.record(.input, .accepted, origin: origin,
                           values: .init(input: .mouseUp, role: .row, ageMilliseconds: 4,
                                         cellCount: 1, labelCount: 1, frameContains: true)),
                  "Accept a typed metadata record")
        try check(a.finish() && b.finish(), "Normal shutdown must flush accepted records")
        try check(try Data(contentsOf: sentinel) == existing, "Existing files must remain unchanged")
        let metadata = try lines(a)
        try check(metadata.count == 2, "Flush includes the header and accepted metadata")
        let allowedKeys: Set<String> = ["schema", "ordinal", "elapsedMilliseconds", "stage", "outcome", "context", "origin", "values"]
        let allowedStrings: Set<String> = ["started", "observed", "input", "accepted", "mouseUp", "row"]
        func inspect(_ value: Any) throws {
            if let text = value as? String {
                try check(allowedStrings.contains(text), "Only enum values may appear as strings")
            } else if let map = value as? [String: Any] {
                for child in map.values { try inspect(child) }
            } else if let list = value as? [Any] {
                for child in list { try inspect(child) }
            }
        }
        for entry in metadata {
            try check(Set(entry.keys) == allowedKeys || Set(entry.keys) == allowedKeys.subtracting(["origin"]),
                      "Only the fixed schema is serialized")
            try inspect(entry)
            let elapsed = entry["elapsedMilliseconds"] as? Int ?? -1
            try check((0...600_000).contains(elapsed), "Use relative bounded time only")
        }

        let childRead = try logger("child-read")
        let copyError = Int(AXError.cannotComplete.rawValue)
        try check(childRead.record(.deferred, .incomplete,
                                   values: .init(childrenFailure: .copyError, childrenCopyError: copyError,
                                                 childrenReportedCount: 3, childrenRequestedCount: 3)),
                  "Accept a typed child-read failure")
        try check(childRead.finish(), "Child-read metadata flushes")
        let childRows = try lines(childRead)
        try check(childRows.count == 2, "A failure adds one event, not one per node")
        let childValues = childRows.last?["values"] as? [String: Any] ?? [:]
        try check(Set(childValues.keys) == ["childrenFailure", "childrenCopyError", "childrenReportedCount", "childrenRequestedCount"],
                  "Unreached stages and raw values must not enter the child-read record")
        try check(childValues["childrenFailure"] as? String == "copyError"
                  && childValues["childrenCopyError"] as? Int == copyError
                  && childValues["childrenReportedCount"] as? Int == 3
                  && childValues["childrenRequestedCount"] as? Int == 3,
                  "Keep the failure enum, signed AX code and counts in their typed fields")

        var recordLimits = MenuCaptureDiagnostics.Limits()
        recordLimits.records = 3
        let capped = try logger("records", limits: recordLimits)
        var accepted = 0
        for _ in 0..<20 { if capped.record(.input, .observed) { accepted += 1 } }
        try check(accepted == 2 && capped.finish(), "The 200-record production cap includes the header")
        try check(try lines(capped).count == 3, "No record beyond the configured cap")
        try check(!capped.record(.input, .observed), "No entries after normal finish")

        var byteLimits = MenuCaptureDiagnostics.Limits()
        byteLimits.bytes = 320
        let bytes = try logger("bytes", limits: byteLimits)
        for _ in 0..<20 { bytes.record(.catalog, .incomplete, values: .init(nodeCount: 800, nodeLimit: true)) }
        try check(bytes.finish(), "Byte-limited logger drains")
        try check(try Data(contentsOf: bytes.fileURL).count <= byteLimits.bytes, "Never exceed byte budget")
        _ = try lines(bytes) // Writes stop before an oversized line, not halfway through one.

        var now: TimeInterval = 100
        let timed = try logger("time", clock: { now })
        now = 99
        try check(!timed.record(.input, .observed), "A backwards clock is not serialized")
        now = 701
        try check(!timed.record(.input, .observed), "Stop accepting after ten minutes")
        try check(timed.finish(), "Expired logger drains previously accepted records")
        try check(try lines(timed).count == 1, "Only the accepted start record remains")

        var pendingLimits = MenuCaptureDiagnostics.Limits()
        pendingLimits.pending = 2
        let paused = DispatchQueue(label: "TileLauncher.menu-diagnostic-validation-paused")
        paused.suspend()
        var resumePending = true
        defer { if resumePending { paused.resume() } }
        let bounded = try logger("pending", limits: pendingLimits, queue: paused)
        let first = bounded.record(.input, .observed)
        let overflow = bounded.record(.input, .observed)
        let waiting = bounded.finish(timeout: 0)
        paused.resume()
        resumePending = false
        try check(first && !overflow && !waiting, "Writer backlog is bounded and enqueue never waits for disk")
        try check(bounded.finish(), "Resuming the writer flushes exactly the accepted backlog")
        try check(try lines(bounded).count == 2, "Overflow records are not queued")

        print("Menu diagnostics: no-opt-in creates no file; unique0600 files preserve existing logs; typed metadata contains no free text.")
        print("Menu diagnostics: bounded pending writes, record/byte/time caps, and normal-termination flush verified with synthetic fixtures only.")
    }
}
#endif
