import Foundation
import Darwin

/// Hold for the lifetime of the app, including launches from other app copies.
/// The kernel releases it on exit or crash. Never unlink the shared lock file.
public final class InstanceLock {
    private let descriptor: Int32

    public init?(url: URL) throws {
        let fd = url.path.withCString { Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600) }
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        descriptor = fd
    }

    deinit { Darwin.close(descriptor) }
}
