import Foundation
import Darwin

/// Frozen at launch: the bundle on disk may be replaced while this process runs.
public struct AppBuild: Codable, Equatable {
    public let version: String
    public let build: String
    public let fingerprint: String

    public init(version: String, build: String, fingerprint: String) {
        self.version = version
        self.build = build
        self.fingerprint = fingerprint
    }
}

/// A PID alone is unsafe after a crash because the system may reuse it.
public struct ProcessIdentity: Codable, Equatable {
    public let pid: Int32
    public let startedSeconds: UInt64
    public let startedMicroseconds: UInt64

    public init(pid: Int32, startedSeconds: UInt64, startedMicroseconds: UInt64) {
        self.pid = pid
        self.startedSeconds = startedSeconds
        self.startedMicroseconds = startedMicroseconds
    }

    public static func read(pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessIdentity(pid: pid, startedSeconds: info.pbi_start_tvsec,
                               startedMicroseconds: info.pbi_start_tvusec)
    }

    public func started(after other: ProcessIdentity) -> Bool {
        if startedSeconds != other.startedSeconds { return startedSeconds > other.startedSeconds }
        return startedMicroseconds > other.startedMicroseconds
    }
}

public struct InstanceOwner: Codable, Equatable {
    public let process: ProcessIdentity
    public let build: AppBuild

    public init(process: ProcessIdentity, build: AppBuild) {
        self.process = process
        self.build = build
    }

    public enum Decision: Equatable { case keepExisting, replaceExisting }
    public func decision(for candidate: InstanceOwner) -> Decision {
        // Last launch wins even when competing processes acquire the launch lock out of order.
        if process.started(after: candidate.process) || build == candidate.build { return .keepExisting }
        return .replaceExisting
    }
}
