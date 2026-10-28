import Foundation

/// Several processes can report the same application bundle URL. Identify the
/// main executable as well, so an embedded agent cannot own its launch gate.
public struct ApplicationLaunchIdentity {
    public let bundlePath: String
    public let bundleID: String?
    public let executablePath: String?
    public init(bundlePath: String, bundleID: String?, executablePath: String?) {
        self.bundlePath = bundlePath; self.bundleID = bundleID; self.executablePath = executablePath
    }
    public func matches(bundlePath: String?, bundleID: String?, executablePath: String?) -> Bool {
        matches(bundleID: bundleID, bundlePath: { bundlePath }, executablePath: { executablePath })
    }
    /// Same rule, but a different known identifier is rejected before the
    /// caller canonicalizes any filesystem path.
    public func matches(bundleID: String?, bundlePath: () -> String?, executablePath: () -> String?) -> Bool {
        if let expected = self.bundleID, expected != bundleID { return false }
        // If metadata is unavailable, a URL alone cannot distinguish helpers.
        guard self.bundleID != nil || self.executablePath != nil else { return false }
        guard self.bundlePath == bundlePath() else { return false }
        if let expected = self.executablePath, expected != executablePath() { return false }
        return true
    }
    /// A new process may run from an alternate or translocated copy. Accept it
    /// only with the same known identifier and main executable name.
    /// The executable name is read only after the identifier matches.
    public func admitsNewProcess(bundleID: String?, executableName: () -> String?) -> Bool {
        guard let expected = self.bundleID, expected == bundleID else { return false }
        guard let executablePath else { return true }
        return executableName() == URL(fileURLWithPath: executablePath).lastPathComponent
    }
}
