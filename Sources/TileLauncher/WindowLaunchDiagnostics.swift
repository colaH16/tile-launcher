import AppKit
import Darwin

/// Temporary opt-in diagnosis. No titles, menu text, URLs or window contents.
/// A fresh private file in /tmp, ten minutes, at most 4 MiB; no upload.
enum WindowLaunchDiagnostics {
    private static let session: Session? = {
        guard CommandLine.arguments.contains("--window-launch-log") else { return nil }
        return Session()
    }()
    static var enabled: Bool { session != nil }
    static func record(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
        session?.record(event, fields())
    }
    private final class Session {
        let queue = DispatchQueue(label: "TileLauncher.window-launch-log", qos: .utility)
        let start = ProcessInfo.processInfo.systemUptime
        let file: FileHandle
        var bytes = 0
        init?() {
            let path = "/tmp/tile-window-launch-\(getpid())-\(UUID().uuidString).jsonl"
            let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return nil }
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            record("start", ["build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "",
                             "pid": getpid(), "readOnly": true])
        }
        func record(_ event: String, _ fields: [String: Any]) {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            guard elapsed <= 600 else { return }
            var row = fields
            row["event"] = event; row["elapsed"] = elapsed
            row["main"] = Thread.isMainThread
            row["option"] = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
            queue.async { [self] in
                guard bytes < 4 * 1024 * 1024,
                      var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
                data.append(10)
                guard bytes + data.count <= 4 * 1024 * 1024 else { return }
                do { try file.write(contentsOf: data); bytes += data.count } catch { bytes = 4 * 1024 * 1024 }
            }
        }
    }
}
