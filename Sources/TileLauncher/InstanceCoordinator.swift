import AppKit
import CryptoKit
import DeckCore

enum InstanceCoordinator {
    static let bundleID = "dev.cola16.TileLauncher"
    static let reopenName = Notification.Name("\(bundleID).reopen")

    static func build(at bundle: URL) throws -> AppBuild {
        // Read fresh data, not Bundle's cached Info dictionary, for in-place updates.
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = info["CFBundleShortVersionString"] as? String,
              let number = info["CFBundleVersion"] as? String,
              let executable = info["CFBundleExecutable"] as? String else {
            throw failure("앱의 버전 정보를 읽지 못했습니다.")
        }
        let fingerprint: String
        if let recorded = info["TileLauncherBuildID"] as? String, !recorded.isEmpty {
            fingerprint = recorded
        } else {
            let binary = try Data(contentsOf: bundle.appendingPathComponent("Contents/MacOS/\(executable)"),
                                  options: .mappedIfSafe)
            fingerprint = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        }
        return AppBuild(version: version, build: number, fingerprint: fingerprint)
    }

    /// Return nil only when another instance should remain. No monitors or windows
    /// have been created yet. The caller holds the returned lock for the app lifetime.
    static func acquire(build: AppBuild) throws -> InstanceLock? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let process = ProcessIdentity.read(pid: getpid()) else {
            throw failure("현재 프로세스를 확인하지 못했습니다.")
        }
        let candidate = InstanceOwner(process: process, build: build)
        let deadline = Date().addingTimeInterval(15)
        let launchURL = directory.appendingPathComponent("launch.lock")
        var launchLock: InstanceLock?
        while launchLock == nil {
            launchLock = try InstanceLock(url: launchURL)
            if launchLock == nil { try wait(until: deadline) }
        }
        defer { withExtendedLifetime(launchLock) {} }

        let lockURL = directory.appendingPathComponent("instance.lock")
        let ownerURL = directory.appendingPathComponent("instance-owner.json")
        var askedToQuit: [Int32: ProcessIdentity] = [:]
        while true {
            if let lock = try InstanceLock(url: lockURL) {
                // A successful termination request is not proof of process exit.
                // NSRunningApplication properties can lag during pre-launch. Read
                // the kernel identity, as for PID reuse checks, rather than its cache.
                while askedToQuit.values.contains(where: { ProcessIdentity.read(pid: $0.pid) == $0 }) {
                    try wait(until: deadline)
                }
                try JSONEncoder().encode(candidate).write(to: ownerURL, options: .atomic)
                return lock
            }

            let existing = readOwner(at: ownerURL)
            if let existing, ProcessIdentity.read(pid: existing.process.pid) == existing.process,
               let app = NSRunningApplication(processIdentifier: existing.process.pid),
               app.bundleIdentifier == bundleID {
                if existing.decision(for: candidate) == .keepExisting {
                    // Its run loop/notification observer may still be starting.
                    if !app.isFinishedLaunching { try wait(until: deadline); continue }
                    reopen()
                    return nil
                }
                if !app.isFinishedLaunching { try wait(until: deadline); continue }
                try requestTermination(app, asked: &askedToQuit)
            } else {
                // Migration from releases that held the lock without an owner record.
                // Their runtime version is unknowable after an in-place bundle update.
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    where app.processIdentifier != process.pid && app.isFinishedLaunching {
                    guard let identity = ProcessIdentity.read(pid: app.processIdentifier),
                          !identity.started(after: process) else { continue }
                    try requestTermination(app, asked: &askedToQuit)
                }
            }
            try wait(until: deadline)
        }
    }

    private static func readOwner(at url: URL) -> InstanceOwner? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4096, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(InstanceOwner.self, from: data)
    }

    private static func requestTermination(_ app: NSRunningApplication, asked: inout [Int32: ProcessIdentity]) throws {
        guard asked[app.processIdentifier] == nil, !app.isTerminated else { return }
        guard let identity = ProcessIdentity.read(pid: app.processIdentifier) else { return }
        asked[app.processIdentifier] = identity
        guard app.terminate() else {
            throw failure("기존 Tile Launcher가 종료 요청을 받지 못했습니다. 기존 앱을 종료한 뒤 다시 열어 주세요.")
        }
    }

    private static func wait(until deadline: Date) throws {
        guard Date() < deadline else {
            throw failure("기존 Tile Launcher의 종료 또는 시작을 기다리는 시간이 초과되었습니다. 기존 앱을 확인한 뒤 다시 열어 주세요.")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private static func reopen() {
        DistributedNotificationCenter.default().postNotificationName(
            reopenName, object: String(getuid()),
            userInfo: ["settings": CommandLine.arguments.contains("--settings")], deliverImmediately: true)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: bundleID, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
