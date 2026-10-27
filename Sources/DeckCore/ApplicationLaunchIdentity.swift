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
        guard self.bundlePath == bundlePath else { return false }
        if let expected = self.bundleID, expected != bundleID { return false }
        if let expected = self.executablePath, expected != executablePath { return false }
        // If metadata is unavailable, a URL alone cannot distinguish helpers.
        return self.bundleID != nil || self.executablePath != nil
    }
}
